"""Camada de repository do User (acesso a dados).

Fica ENTRE o service (regras de negócio) e o banco. A responsabilidade aqui é
SÓ persistir e consultar — nada de hash de senha, JWT, schemas Pydantic, rotas
ou regra de negócio. O service decide o "quê"; o repository sabe o "como" falar
com o Postgres via SQLAlchemy 2.0 (estilo moderno: select()/db.get()/db.scalar()).

Sessão: o repository RECEBE a Session pronta como parâmetro (db: Session). Ele
NÃO cria sessão, NÃO importa get_db e NÃO fecha a sessão — o ciclo de vida é do
caller (a dependency get_db do FastAPI faz o try/finally).

Funções de módulo (não classe): a arquitetura aprovada pede funções soltas.
São operações stateless sobre uma Session passada por parâmetro; uma classe só
agregaria o `db` no __init__ sem ganho real no MVP, e funções compõem melhor
com a injeção de dependência do FastAPI.
"""

import uuid

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.user import User


def get_by_email(db: Session, email: str) -> User | None:
    """Busca um usuário pelo e-mail; retorna o User ou None.

    Usado no register (checar duplicado antes de inserir) e no login (achar o
    usuário pela credencial). Estilo 2.0: select() + db.scalar(), que devolve a
    PRIMEIRA coluna da primeira linha (a entidade User) ou None — sem o legado
    db.query(...).filter(...).first(). Como email é UNIQUE no banco, no máximo
    uma linha casa.
    """
    return db.scalar(select(User).where(User.email == email))


def get_by_id(db: Session, user_id: uuid.UUID) -> User | None:
    """Busca um usuário pela PK (UUID); retorna o User ou None.

    Usado no GET /auth/me. Aqui preferimos db.get(User, user_id) em vez de
    select(): é o caminho canônico do 2.0 para lookup por PK e consulta o
    identity-map da sessão primeiro — se a entidade já foi carregada nesta
    Session, retorna sem ir ao banco. Para acesso por chave primária isso é mais
    direto e barato que montar um select().
    """
    return db.get(User, user_id)


def create(db: Session, *, name: str, email: str, password_hash: str) -> User:
    """Cria e persiste um novo usuário; retorna a instância com os campos do
    banco já populados.

    Recebe CAMPOS (name, email, password_hash), não um objeto User pronto: a
    montagem da entidade é detalhe da persistência e fica encapsulada aqui — o
    service não precisa importar o model nem saber montar o ORM. Mantém a
    fronteira limpa (o service passa dados primitivos) e a assinatura explícita.

    Segurança: recebe password_hash JÁ hasheado. O repository NÃO calcula hash —
    quem gera é o service/security e PASSA PRONTO. `name`, `email` e
    `password_hash` são keyword-only (após o *) para evitar troca acidental de
    posição entre os três `str`.

    Fronteira transacional — o repository dá o commit (commit + refresh):
    para o MVP, cada operação de escrita é sua própria unidade de trabalho, o
    que torna o repository utilizável de forma autônoma e simplifica o service.
    Tradeoff assumido: NÃO há transação multi-passo orquestrada pelo service
    (ex.: criar usuário + outra escrita no mesmo commit atômico). Se isso
    aparecer, a fronteira migra para o service (repository só faz flush; quem
    commita é a unidade de trabalho de cima). Para o cadastro simples atual,
    commitar aqui é o tradeoff certo.

    flush/refresh — popular os server_default: id (gen_random_uuid()),
    created_at/updated_at (now()) e is_active (true) só existem no objeto Python
    DEPOIS de o banco processar o INSERT. O commit faz o flush (envia o INSERT)
    e, por padrão, expira os atributos da instância; o refresh() recarrega a
    linha gravada, devolvendo o User com TODOS os defaults preenchidos — pronto
    pro service/schema de saída ler id e created_at.

    IntegrityError (e-mail duplicado): NÃO traduzimos aqui — deixamos a exceção
    PROPAGAR. A unicidade é garantida pela constraint UNIQUE no banco (fonte da
    verdade, livre de corrida; uma checagem prévia no service tem janela de
    concorrência). Traduzir IntegrityError em 409 Conflict é decisão de POLÍTICA
    HTTP, que é do service/handler, não do repository. Capturar para traduzir
    acoplaria a camada de dados à semântica de API e mascararia outras violações
    de constraint. Então a exceção sobe e o service a converte na resposta certa.

    PORÉM, como o commit que FALHOU foi disparado AQUI, o repository é o dono do
    rollback: um commit que estoura deixa a Session em estado abortado e a próxima
    operação nela levantaria PendingRollbackError. A dependency get_db só faz
    close() (não rollback()), então, sem isto, vazaríamos uma sessão quebrada para
    o caller. Fazemos rollback e RE-LEVANTAMOS a MESMA exceção (raise nu) — a
    decisão de política (virar 409) continua intacta no service, mas a sessão volta
    utilizável. Não engolimos o erro nem logamos nada (e-mail é PII).
    """
    # Monta a entidade só com os campos de entrada; os defaults vêm do banco.
    user = User(name=name, email=email, password_hash=password_hash)
    db.add(user)
    try:
        # commit envia o INSERT (flush) e confirma a transação.
        db.commit()
    except IntegrityError:
        # Restaura a sessão antes de propagar (ex.: e-mail duplicado -> UNIQUE).
        db.rollback()
        raise
    # refresh recarrega a linha gravada -> popula id, created_at, is_active etc.
    db.refresh(user)
    return user


def set_password_hash(db: Session, *, user: User, password_hash: str) -> User:
    """Atualiza o hash da senha de um usuário já carregado (usado pelo script de
    reset). Recebe o hash JÁ pronto — quem gera é o service/security."""
    user.password_hash = password_hash
    db.commit()
    db.refresh(user)
    return user


def get_by_username(db: Session, username: str) -> User | None:
    """Busca sem CAIXA: a unicidade do @username é por LOWER(username), então a
    consulta precisa usar o mesmo critério do índice (senão o Postgres nem o
    aproveitaria, e '@Juan' passaria como livre com '@juan' já existente)."""
    return db.scalar(select(User).where(func.lower(User.username) == username.lower()))


def update_profile(
    db: Session,
    *,
    user: User,
    name: str | None = None,
    username: str | None = None,
    bio: str | None = None,
) -> User:
    """Atualização PARCIAL da identidade pública. Só toca no que foi enviado —
    quem não manda `bio` não a apaga sem querer.

    O IntegrityError (corrida de dois @iguais no mesmo instante) PROPAGA: a
    política HTTP (409) é decisão do service/rota, não da camada de dados. Mas o
    rollback é nosso, porque o commit que falhou saiu daqui."""
    if name is not None:
        user.name = name
    if username is not None:
        user.username = username
    if bio is not None:
        user.bio = bio
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise
    db.refresh(user)
    return user


def set_avatar_path(db: Session, *, user: User, path: str | None) -> User:
    """Grava (após o upload) ou LIMPA (None, na remoção) o caminho do avatar."""
    user.avatar_path = path
    db.commit()
    db.refresh(user)
    return user
