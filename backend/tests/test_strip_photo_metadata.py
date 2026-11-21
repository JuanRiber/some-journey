"""A faxina das fotos que já estavam no Storage.

O script grava por cima do arquivo original — e não tem volta. Por isso o que
estes testes mais prendem é o que ele NÃO faz: não grava sem `--apply`, não
toca no que já está limpo, não toca no que não consegue percorrer, e nunca
grava uma imagem diferente da que estava lá.
"""

import uuid

import pytest
from sqlalchemy import text

from app.core import storage
from app.models.memory import MemoryImage
from scripts import strip_photo_metadata as faxina
from tests._images import JPEG, PNG, encode, pixels
from tests.test_image_metadata import _SEGREDOS, _jpeg_de_celular, _png_com_tudo


@pytest.fixture()
def bucket(monkeypatch):
    """Um Storage de mentira, com leitura e gravação."""

    class Bucket:
        arquivos: dict[str, bytes]
        gravacoes: list[str]
        falha_ao_gravar: bool

    b = Bucket()
    b.arquivos = {}
    b.gravacoes = []
    b.falha_ao_gravar = False
    monkeypatch.setattr(storage, "enabled", lambda: True)
    monkeypatch.setattr(storage, "download", lambda path: b.arquivos.get(path))

    def upload(path, data, mime):
        if b.falha_ao_gravar:
            raise storage.StorageError("fora do ar")
        b.gravacoes.append(path)
        b.arquivos[path] = data

    monkeypatch.setattr(storage, "upload", upload)
    monkeypatch.setattr(storage, "delete", lambda *a, **k: None)
    monkeypatch.setattr(storage, "sign_urls", lambda paths, ttl=None: {})
    return b


@pytest.fixture()
def acervo(client, auth_headers, db_session, bucket):
    """Uma conta com foto de memória, capa e avatar — os três com metadados."""
    h = auth_headers()
    mid = client.post(
        "/memories",
        headers=h,
        json={
            "text": "x",
            "latitude": -3.73,
            "longitude": -38.52,
            "occurred_at": "2026-05-01T12:00:00Z",
        },
    ).json()["id"]
    jid = client.post("/journeys", headers=h, json={"title": "Litoral"}).json()["id"]
    db_session.add(
        MemoryImage(memory_id=uuid.UUID(mid), image_path="m/foto.jpg", position=1)
    )
    db_session.execute(
        text("UPDATE journeys SET cover_image_path = 'j/capa.png' WHERE id = :id"),
        {"id": jid},
    )
    db_session.execute(text("UPDATE users SET avatar_path = 'u/avatar.jpg'"))
    db_session.commit()
    bucket.arquivos.update(
        {
            "m/foto.jpg": _jpeg_de_celular(),
            "j/capa.png": _png_com_tudo(),
            "u/avatar.jpg": _jpeg_de_celular(orientacao=3),
        }
    )
    return h, mid


def test_sem_apply_so_conta_e_nao_grava_nada(acervo, bucket):
    antes = dict(bucket.arquivos)

    r = faxina.run(apply=False)

    assert (r.examined, r.cleaned, r.already_clean) == (3, 3, 0)
    assert r.bytes_removed > 0
    assert bucket.gravacoes == []
    assert bucket.arquivos == antes


def test_com_apply_as_tres_ficam_sem_metadados_e_com_os_mesmos_pixels(acervo, bucket):
    antes = dict(bucket.arquivos)

    r = faxina.run(apply=True)

    assert (r.examined, r.cleaned, r.failed_upload) == (3, 3, 0)
    assert sorted(bucket.gravacoes) == sorted(antes), "grava no MESMO caminho"
    for caminho, original in antes.items():
        limpo = bucket.arquivos[caminho]
        for segredo in _SEGREDOS:
            assert segredo not in limpo
        assert pixels(limpo) == pixels(original)


def test_rodar_de_novo_nao_grava_mais_nada(acervo, bucket):
    faxina.run(apply=True)
    bucket.gravacoes.clear()

    r = faxina.run(apply=True)

    assert (r.cleaned, r.already_clean) == (0, 3)
    assert bucket.gravacoes == []


def test_foto_que_ja_estava_limpa_nao_e_regravada(acervo, bucket):
    bucket.arquivos = {"m/foto.jpg": JPEG, "j/capa.png": PNG, "u/avatar.jpg": JPEG}

    r = faxina.run(apply=True)

    assert r.already_clean == 3
    assert bucket.gravacoes == []


def test_arquivo_que_nao_da_para_percorrer_fica_como_esta(acervo, bucket):
    cortada = _jpeg_de_celular()[:-2]
    bucket.arquivos["m/foto.jpg"] = cortada
    bucket.arquivos["j/capa.png"] = b"isto nao e imagem"

    r = faxina.run(apply=True)

    assert (r.not_cleanable, r.cleaned) == (2, 1)
    assert bucket.arquivos["m/foto.jpg"] == cortada
    assert bucket.arquivos["j/capa.png"] == b"isto nao e imagem"
    assert bucket.gravacoes == ["u/avatar.jpg"]


def test_arquivo_que_sumiu_do_storage_e_contado_e_o_resto_segue(acervo, bucket):
    del bucket.arquivos["j/capa.png"]

    r = faxina.run(apply=True)

    assert (r.unreadable, r.cleaned) == (1, 2)


def test_falha_ao_gravar_nao_e_contada_como_limpa(acervo, bucket):
    bucket.falha_ao_gravar = True

    r = faxina.run(apply=True)

    assert (r.cleaned, r.failed_upload) == (0, 3)


def test_o_que_foi_apagado_fica_de_fora(client, acervo, db_session, bucket):
    """Memória apagada e foto removida não entram: o arquivo delas é assunto do
    expurgo, não da faxina."""
    h, mid = acervo
    client.delete(f"/memories/{mid}", headers=h)

    with faxina.SessionLocal() as db:
        caminhos = faxina.stored_paths(db)

    assert caminhos == ["j/capa.png", "u/avatar.jpg"]


def test_uma_limpeza_instavel_nunca_e_gravada(acervo, bucket, monkeypatch):
    """A trava antes de gravar por cima: se limpar o limpo não der no mesmo
    arquivo, algo está errado — e o original é deixado em paz."""
    chamadas = {"n": 0}

    def instavel(data, mime):
        chamadas["n"] += 1
        return data[:-1] if chamadas["n"] % 2 else data + b"x"

    monkeypatch.setattr(faxina, "strip_metadata", instavel)
    antes = dict(bucket.arquivos)

    r = faxina.run(apply=True)

    assert (r.not_cleanable, r.cleaned) == (3, 0)
    assert bucket.arquivos == antes


def test_o_script_sem_argumento_e_ensaio(acervo, bucket, capsys):
    assert faxina.main([]) == 0
    saida = capsys.readouterr().out
    assert "ensaio: nada foi gravado" in saida
    assert "seriam limpas ............ 3" in saida
    assert bucket.gravacoes == []
    for caminho in bucket.arquivos:
        assert caminho not in saida, "o script não imprime caminho"


def test_o_script_com_apply_grava_e_diz_quanto(acervo, bucket, capsys):
    assert faxina.main(["--apply"]) == 0
    saida = capsys.readouterr().out
    assert "limpas agora ............ 3" in saida
    assert len(bucket.gravacoes) == 3


def test_sem_storage_configurado_o_script_avisa_e_sai(monkeypatch, capsys):
    monkeypatch.setattr(storage, "enabled", lambda: False)
    assert faxina.main(["--apply"]) == 1
    assert "Storage não configurado" in capsys.readouterr().out


class _Resposta:
    def __init__(self, status_code: int, content: bytes = b"") -> None:
        self.status_code = status_code
        self.content = content


@pytest.mark.parametrize(
    ("resposta", "esperado"),
    [(_Resposta(200, b"bytes"), b"bytes"), (_Resposta(404), None), (_Resposta(500), None)],
)
def test_download_devolve_os_bytes_ou_nada(monkeypatch, resposta, esperado):
    pedidos = []

    class Cliente:
        def __init__(self, *a, **k) -> None: ...
        def __enter__(self): return self
        def __exit__(self, *a) -> None: ...
        def get(self, url, headers=None):
            pedidos.append((url, headers))
            return resposta

    monkeypatch.setattr(storage, "enabled", lambda: True)
    monkeypatch.setattr(storage.settings, "SUPABASE_URL", "https://x.supabase.co")
    monkeypatch.setattr(storage.settings, "SUPABASE_SERVICE_KEY", "chave")
    monkeypatch.setattr(storage.httpx, "Client", Cliente)

    assert storage.download("m/a.jpg") == esperado
    (url, headers), = pedidos
    # A mesma URL do upload e do delete, com outro verbo, e autenticada.
    assert url == "https://x.supabase.co/storage/v1/object/memories/m/a.jpg"
    assert headers["Authorization"] == "Bearer chave"


def test_a_imagem_de_teste_grande_tambem_passa():
    """Uma foto com cara de foto, não só as miniaturas dos outros testes."""
    original = encode("JPEG", tamanho=(640, 480), quality=88, progressive=True)
    from app.core.image_metadata import strip_metadata

    assert pixels(strip_metadata(original, "image/jpeg")) == pixels(original)
