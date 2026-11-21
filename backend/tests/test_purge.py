"""O expurgo: o que foi apagado "de leve" sai de vez depois do prazo.

Apagar no Some Journey é marcar `deleted_at`. Protege de um toque errado — e,
sem expurgo, significava que nada jamais saía: a memória apagada há um ano
seguia no banco, com as fotos no Storage. Estes testes prendem o prazo (nem um
dia antes), o que vai junto de cada coisa, e que nenhum arquivo fica sem
registro quando o Storage falha.
"""

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import func, select, text

from app.core import storage
from app.core.config import settings
from app.models.file_deletion import PendingFileDeletion
from app.models.journey import Journey, JourneyMemory
from app.models.life_phase import LifePhase
from app.models.memory import Memory, MemoryImage, MemoryMusic
from app.models.password_reset import PasswordResetToken
from app.models.refresh_token import RefreshToken
from app.models.track import JourneyTrack, JourneyTrackPoint
from app.services import purge_service


@pytest.fixture()
def cofre(monkeypatch):
    class Cofre:
        removidos: list[str]
        recusa: set[str]

    c = Cofre()
    c.removidos = []
    c.recusa = set()
    monkeypatch.setattr(storage, "enabled", lambda: True)

    def remove(path: str) -> bool:
        if path in c.recusa:
            return False
        c.removidos.append(path)
        return True

    monkeypatch.setattr(storage, "remove", remove)
    monkeypatch.setattr(storage, "delete", lambda *a, **k: None)
    monkeypatch.setattr(storage, "sign_urls", lambda paths, ttl=None: {})
    return c


def _memoria(client, h, **over) -> str:
    corpo = {
        "text": "x",
        "latitude": -3.73,
        "longitude": -38.52,
        "occurred_at": "2026-05-01T12:00:00Z",
    }
    corpo.update(over)
    return client.post("/memories", headers=h, json=corpo).json()["id"]


def _foto(db_session, memoria_id: str, caminho: str) -> None:
    db_session.add(
        MemoryImage(memory_id=uuid.UUID(memoria_id), image_path=caminho, position=1)
    )
    db_session.commit()


def _envelhecer(db_session, tabela: str, dias: int, onde: str = "deleted_at IS NOT NULL"):
    """Faz o que foi apagado parecer apagado há `dias`."""
    db_session.execute(
        text(
            f"UPDATE {tabela} SET deleted_at = now() - make_interval(days => :d) "
            f"WHERE {onde}"
        ),
        {"d": dias},
    )
    db_session.commit()


def _conta(db_session, model) -> int:
    return db_session.scalar(select(func.count()).select_from(model)) or 0


# --- o prazo ----------------------------------------------------------------


def test_o_padrao_do_prazo_e_trinta_dias():
    assert settings.PURGE_DELETED_AFTER_DAYS == 30


def test_memoria_apagada_ha_mais_que_o_prazo_sai_com_as_fotos(
    client, auth_headers, db_session, cofre
):
    h = auth_headers()
    mid = _memoria(client, h)
    _foto(db_session, mid, "m/velha.jpg")
    client.delete(f"/memories/{mid}", headers=h)
    _envelhecer(db_session, "memories", 31)

    r = purge_service.purge_expired(db_session)

    assert r.memories == 1
    assert _conta(db_session, Memory) == 0
    assert _conta(db_session, MemoryImage) == 0
    assert cofre.removidos == ["m/velha.jpg"]
    assert _conta(db_session, PendingFileDeletion) == 0


def test_dentro_do_prazo_nada_sai(client, auth_headers, db_session, cofre):
    h = auth_headers()
    mid = _memoria(client, h)
    _foto(db_session, mid, "m/recente.jpg")
    client.delete(f"/memories/{mid}", headers=h)
    _envelhecer(db_session, "memories", 29)

    r = purge_service.purge_expired(db_session)

    assert r.rows == 0
    assert _conta(db_session, Memory) == 1
    assert cofre.removidos == []


def test_o_que_nao_foi_apagado_nunca_sai(client, auth_headers, db_session, cofre):
    h = auth_headers()
    mid = _memoria(client, h)
    _foto(db_session, mid, "m/viva.jpg")
    db_session.execute(
        text("UPDATE memories SET created_at = now() - interval '5 years'")
    )
    db_session.commit()

    r = purge_service.purge_expired(db_session)

    assert r.rows == 0 and r.files_queued == 0
    assert client.get(f"/memories/{mid}", headers=h).status_code == 200
    assert cofre.removidos == []


def test_o_prazo_pode_ser_outro(client, auth_headers, db_session, cofre):
    h = auth_headers()
    client.delete(f"/memories/{_memoria(client, h)}", headers=h)
    _envelhecer(db_session, "memories", 10)

    assert purge_service.purge_expired(db_session, older_than_days=30).memories == 0
    assert purge_service.purge_expired(db_session, older_than_days=7).memories == 1


# --- o que vai junto de cada coisa ------------------------------------------


def test_jornada_vencida_leva_capa_vinculos_e_percurso_mas_nao_a_memoria(
    client, auth_headers, db_session, cofre
):
    h = auth_headers()
    mid = _memoria(client, h)
    jid = client.post("/journeys", headers=h, json={"title": "Litoral"}).json()["id"]
    client.post(f"/journeys/{jid}/start", headers=h)
    client.post(f"/journeys/{jid}/points", headers=h, json={"memory_id": mid})
    tid = client.post(
        f"/journeys/{jid}/tracks/start", headers=h, json={"source": "gps_live"}
    ).json()["id"]
    client.post(
        f"/journeys/{jid}/tracks/{tid}/points",
        headers=h,
        json={
            "points": [
                {"latitude": -3.7, "longitude": -38.5, "recorded_at": "2026-05-01T12:00:00Z"}
            ]
        },
    )
    db_session.execute(
        text("UPDATE journeys SET cover_image_path = 'j/capa.jpg' WHERE id = :id"),
        {"id": jid},
    )
    db_session.commit()
    client.delete(f"/journeys/{jid}", headers=h)
    _envelhecer(db_session, "journeys", 40)

    r = purge_service.purge_expired(db_session)

    assert r.journeys == 1
    assert _conta(db_session, Journey) == 0
    assert _conta(db_session, JourneyMemory) == 0
    assert _conta(db_session, JourneyTrack) == 0
    assert _conta(db_session, JourneyTrackPoint) == 0
    assert cofre.removidos == ["j/capa.jpg"]
    # Excluir a jornada nunca apagou as memórias dela — o expurgo também não.
    assert client.get(f"/memories/{mid}", headers=h).status_code == 200


def test_trecho_de_gps_apagado_sai_com_os_pontos_e_a_jornada_fica(
    client, auth_headers, db_session, cofre
):
    h = auth_headers()
    jid = client.post("/journeys", headers=h, json={"title": "Trilha"}).json()["id"]
    client.post(f"/journeys/{jid}/start", headers=h)
    tid = client.post(
        f"/journeys/{jid}/tracks/start", headers=h, json={"source": "gps_live"}
    ).json()["id"]
    client.post(
        f"/journeys/{jid}/tracks/{tid}/points",
        headers=h,
        json={
            "points": [
                {"latitude": -3.7, "longitude": -38.5, "recorded_at": "2026-05-01T12:00:00Z"}
            ]
        },
    )
    client.post(f"/journeys/{jid}/tracks/{tid}/finish", headers=h)
    client.delete(f"/journeys/{jid}/tracks/{tid}", headers=h)
    _envelhecer(db_session, "journey_tracks", 31)

    r = purge_service.purge_expired(db_session)

    assert r.tracks == 1
    assert _conta(db_session, JourneyTrackPoint) == 0
    assert client.get(f"/journeys/{jid}", headers=h).status_code == 200


def test_fase_apagada_sai_e_as_memorias_que_eram_dela_ficam(
    client, auth_headers, db_session, cofre
):
    h = auth_headers()
    fase = client.post("/life-phases", headers=h, json={"name": "Faculdade"}).json()
    mid = _memoria(client, h, life_phase_id=fase["id"])
    client.delete(f"/life-phases/{fase['id']}", headers=h)
    _envelhecer(db_session, "life_phases", 31)

    r = purge_service.purge_expired(db_session)

    assert r.life_phases == 1
    assert _conta(db_session, LifePhase) == 0
    assert client.get(f"/memories/{mid}", headers=h).status_code == 200


def test_foto_e_musica_removidas_de_uma_memoria_que_continua(
    client, auth_headers, db_session, cofre
):
    h = auth_headers()
    mid = _memoria(client, h)
    _foto(db_session, mid, "m/tirada.jpg")
    faixa = client.post(
        f"/memories/{mid}/music",
        headers=h,
        json={
            "provider": "itunes",
            "external_id": "1",
            "title": "Sozinho",
            "artist": "Caetano Veloso",
        },
    ).json()["music"][0]
    foto = db_session.scalars(select(MemoryImage)).one()
    client.delete(f"/memories/{mid}/images/{foto.id}", headers=h)
    client.delete(f"/memories/{mid}/music/{faixa['id']}", headers=h)
    _envelhecer(db_session, "memory_images", 31)
    _envelhecer(db_session, "memory_music", 31)

    r = purge_service.purge_expired(db_session)

    assert r.detached == 2
    assert _conta(db_session, MemoryImage) == 0
    assert _conta(db_session, MemoryMusic) == 0
    # O arquivo já tinha sido apagado na hora, em melhor-esforço; o expurgo
    # garante — apagar o que não existe mais é inofensivo.
    assert cofre.removidos == ["m/tirada.jpg"]
    assert client.get(f"/memories/{mid}", headers=h).status_code == 200


def test_tokens_vencidos_saem(client, auth_headers, db_session, cofre):
    auth_headers()
    usuario = db_session.execute(text("SELECT id FROM users")).scalar_one()
    agora = datetime.now(UTC)
    db_session.add_all(
        [
            PasswordResetToken(
                user_id=usuario, token_hash="a" * 64, expires_at=agora - timedelta(days=2)
            ),
            PasswordResetToken(
                user_id=usuario, token_hash="b" * 64, expires_at=agora - timedelta(hours=1)
            ),
            RefreshToken(
                user_id=usuario,
                family_id=uuid.uuid4(),
                token_hash="c" * 64,
                expires_at=agora - timedelta(minutes=1),
            ),
        ]
    )
    db_session.commit()

    r = purge_service.purge_expired(db_session)

    assert r.tokens == 2
    # O de recuperação vencido há uma hora fica; o refresh do login também.
    assert [t.token_hash for t in db_session.scalars(select(PasswordResetToken))] == [
        "b" * 64
    ]
    assert _conta(db_session, RefreshToken) == 1


# --- os arquivos ------------------------------------------------------------


def test_storage_que_falha_nao_perde_o_caminho(client, auth_headers, db_session, cofre):
    h = auth_headers()
    mid = _memoria(client, h)
    _foto(db_session, mid, "m/teimosa.jpg")
    client.delete(f"/memories/{mid}", headers=h)
    _envelhecer(db_session, "memories", 31)
    cofre.recusa = {"m/teimosa.jpg"}

    r = purge_service.purge_expired(db_session)

    assert (r.memories, r.files_queued, r.files_deleted, r.files_failed) == (1, 1, 0, 1)
    assert _conta(db_session, Memory) == 0, "a linha saiu mesmo assim"
    (pendente,) = db_session.scalars(select(PendingFileDeletion)).all()
    assert (pendente.path, pendente.attempts) == ("m/teimosa.jpg", 1)
    assert pendente.last_attempt_at is not None


def test_a_passada_seguinte_tenta_de_novo_e_esvazia_a_fila(db_session, cofre):
    purge_service.enqueue_files(db_session, ["a.jpg", "b.jpg"])
    db_session.commit()
    cofre.recusa = {"a.jpg"}
    assert purge_service.drain_file_deletions(db_session) == (1, 1)

    cofre.recusa = set()
    assert purge_service.drain_file_deletions(db_session) == (1, 0)

    assert sorted(cofre.removidos) == ["a.jpg", "b.jpg"]
    assert _conta(db_session, PendingFileDeletion) == 0


def test_arquivo_que_nunca_sai_nao_segura_os_outros(db_session, cofre):
    purge_service.enqueue_files(db_session, ["preso.jpg"])
    db_session.commit()
    cofre.recusa = {"preso.jpg"}
    purge_service.drain_file_deletions(db_session)
    purge_service.enqueue_files(db_session, ["novo-1.jpg", "novo-2.jpg"])
    db_session.commit()

    purge_service.drain_file_deletions(db_session, limit=2)

    assert sorted(cofre.removidos) == ["novo-1.jpg", "novo-2.jpg"]


def test_sem_storage_configurado_a_fila_espera(db_session, monkeypatch):
    monkeypatch.setattr(storage, "enabled", lambda: False)
    purge_service.enqueue_files(db_session, ["espera.jpg"])
    db_session.commit()

    assert purge_service.drain_file_deletions(db_session) == (0, 0)

    (pendente,) = db_session.scalars(select(PendingFileDeletion)).all()
    assert pendente.attempts == 0, "não é falha do arquivo: não havia a quem pedir"


def test_caminho_repetido_ou_vazio_nao_entra_duas_vezes(db_session, cofre):
    assert purge_service.enqueue_files(db_session, ["x.jpg", "x.jpg", None, ""]) == 1
    db_session.commit()
    assert _conta(db_session, PendingFileDeletion) == 1


# --- o que roda sozinho -----------------------------------------------------


def test_rodar_duas_vezes_apaga_uma_vez_so(client, auth_headers, db_session, cofre):
    h = auth_headers()
    mid = _memoria(client, h)
    _foto(db_session, mid, "m/uma.jpg")
    client.delete(f"/memories/{mid}", headers=h)
    _envelhecer(db_session, "memories", 31)

    primeira = purge_service.purge_expired(db_session)
    segunda = purge_service.purge_expired(db_session)

    assert primeira.memories == 1
    assert (segunda.rows, segunda.files_queued, segunda.files_deleted) == (0, 0, 0)
    assert cofre.removidos == ["m/uma.jpg"]


def test_a_previa_conta_sem_apagar(client, auth_headers, db_session, cofre):
    h = auth_headers()
    client.delete(f"/memories/{_memoria(client, h)}", headers=h)
    _envelhecer(db_session, "memories", 31)

    previa = purge_service.preview(db_session)

    assert previa.memories == 1
    assert _conta(db_session, Memory) == 1


def test_a_previa_roda_num_banco_que_ainda_nao_tem_a_fila(
    client, auth_headers, db_session, cofre
):
    """É o uso para que a prévia existe: olhar o que sairia ANTES de publicar,
    quando o banco de produção ainda não recebeu a migration da fila."""
    h = auth_headers()
    client.delete(f"/memories/{_memoria(client, h)}", headers=h)
    _envelhecer(db_session, "memories", 31)
    db_session.execute(text("ALTER TABLE pending_file_deletions RENAME TO fila_fora"))
    db_session.commit()
    try:
        previa = purge_service.preview(db_session)
    finally:
        db_session.rollback()
        db_session.execute(
            text("ALTER TABLE fila_fora RENAME TO pending_file_deletions")
        )
        db_session.commit()

    assert (previa.memories, previa.files_queued) == (1, 0)


def test_o_script_em_dry_run_nao_apaga(client, auth_headers, db_session, cofre, capsys):
    from scripts import purge_deleted

    h = auth_headers()
    client.delete(f"/memories/{_memoria(client, h)}", headers=h)
    _envelhecer(db_session, "memories", 31)

    assert purge_deleted.main(["--dry-run"]) == 0
    assert "memórias ............ 1" in capsys.readouterr().out
    assert _conta(db_session, Memory) == 1

    assert purge_deleted.main([]) == 0
    assert _conta(db_session, Memory) == 0


def test_uma_passada_do_agendador_usa_sessao_propria(
    client, auth_headers, db_session, cofre
):
    h = auth_headers()
    client.delete(f"/memories/{_memoria(client, h)}", headers=h)
    _envelhecer(db_session, "memories", 31)

    relatorio = purge_service.run_once()

    assert relatorio.memories == 1
    assert _conta(db_session, Memory) == 0


def test_o_agendador_so_roda_sozinho_em_producao():
    """Fora de produção a API não apaga nada por conta própria: nem a suíte no
    meio de outro teste, nem uma API de desenvolvimento deixada de pé — cujo
    `.env` alcança o bucket de verdade."""
    from app.core.config import Settings

    def intervalo(**env) -> float:
        return Settings(
            DATABASE_URL="postgresql+psycopg://x:y@localhost/z",
            JWT_SECRET_KEY="k" * 40,
            _env_file=None,
            **env,
        ).purge_interval_hours

    assert settings.purge_interval_hours == 0, "a suíte roda com APP_ENV=test"
    assert intervalo(APP_ENV="development") == 0
    assert intervalo(APP_ENV="production", CORS_ALLOW_ORIGIN_REGEX=None) == 6
    assert intervalo(APP_ENV="production", PURGE_INTERVAL_HOURS=0) == 0
    assert intervalo(APP_ENV="development", PURGE_INTERVAL_HOURS=1) == 1


def test_o_laco_do_agendador_sobe_e_desce_com_a_api(monkeypatch):
    """O laço nasce no início da API e é cancelado no fim — e a primeira
    passada espera, não roda no boot."""
    import asyncio

    from app import main

    monkeypatch.setattr(settings, "PURGE_INTERVAL_HOURS", 1.0)
    rodou = []
    monkeypatch.setattr(main.purge_service, "run_once", lambda: rodou.append(1))

    async def ciclo() -> bool:
        async with main.lifespan(main.app):
            tarefas = [t for t in asyncio.all_tasks() if t.get_coro().__name__ == "_purge_loop"]
            assert len(tarefas) == 1
            await asyncio.sleep(0)
        await asyncio.sleep(0)
        return tarefas[0].cancelled() or tarefas[0].done()

    assert asyncio.run(ciclo()) is True
    assert rodou == [], "a primeira passada espera a API assentar"


# --- o storage --------------------------------------------------------------


class _Resposta:
    def __init__(self, status_code: int, text: str = "") -> None:
        self.status_code = status_code
        self.text = text


@pytest.mark.parametrize(
    ("resposta", "saiu"),
    [
        (_Resposta(200, "{}"), True),
        (_Resposta(404, ""), True),
        (_Resposta(400, '{"statusCode":"404","error":"not_found","message":"Object not found"}'), True),
        (_Resposta(400, '{"error":"Invalid key"}'), False),
        (_Resposta(401, ""), False),
        (_Resposta(500, ""), False),
    ],
)
def test_remove_so_diz_que_saiu_quando_saiu(monkeypatch, resposta, saiu):
    class Cliente:
        def __init__(self, *a, **k) -> None: ...
        def __enter__(self): return self
        def __exit__(self, *a) -> None: ...
        def request(self, *a, **k): return resposta

    monkeypatch.setattr(storage, "enabled", lambda: True)
    monkeypatch.setattr(storage.settings, "SUPABASE_URL", "https://x.supabase.co")
    monkeypatch.setattr(storage.httpx, "Client", Cliente)

    assert storage.remove("m/a.jpg") is saiu


def test_remove_com_rede_fora_e_falso_sem_levantar(monkeypatch):
    import httpx

    class Cliente:
        def __init__(self, *a, **k) -> None: ...
        def __enter__(self): return self
        def __exit__(self, *a) -> None: ...
        def request(self, *a, **k): raise httpx.ConnectError("sem rede")

    monkeypatch.setattr(storage, "enabled", lambda: True)
    monkeypatch.setattr(storage.settings, "SUPABASE_URL", "https://x.supabase.co")
    monkeypatch.setattr(storage.httpx, "Client", Cliente)

    assert storage.remove("m/a.jpg") is False
