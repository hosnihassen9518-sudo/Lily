from pathlib import Path
from alembic import command
from alembic.config import Config

def upgrade_database(engine):
    root = Path(__file__).resolve().parents[2]
    config = Config(str(root / 'alembic.ini'))
    config.set_main_option('script_location', str(root / 'migrations'))
    with engine.begin() as connection:
        config.attributes['connection'] = connection
        command.upgrade(config, 'head')
