from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    """Base declarativa: classe-mãe de todos os models ORM do Some Journey.

    Cada model (ex.: User) vai herdar desta classe. O SQLAlchemy usa o
    Base.metadata para registrar todas as tabelas mapeadas.
    """

    pass
