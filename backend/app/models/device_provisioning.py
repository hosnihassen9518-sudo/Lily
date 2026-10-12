from sqlalchemy import ForeignKey,Text,String,UniqueConstraint
from sqlalchemy.orm import Mapped,mapped_column
from app.db.session import Base

class DeviceProvisioning(Base):
    __tablename__='device_provisioning'
    device_id:Mapped[int]=mapped_column(ForeignKey('devices.id',ondelete='CASCADE'),primary_key=True)
    encrypted_config:Mapped[str]=mapped_column(Text)

class WidgetCredential(Base):
    __tablename__='widget_credentials'
    __table_args__=(UniqueConstraint('session_id','installation_id',name='uq_widget_session_installation'),)
    token_hash:Mapped[str]=mapped_column(String(64),primary_key=True)
    session_id:Mapped[str]=mapped_column(ForeignKey('mobile_sessions.id',ondelete='CASCADE'),index=True)
    installation_id:Mapped[str]=mapped_column(String(32))
