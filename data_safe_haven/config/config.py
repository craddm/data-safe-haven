"""Configuration file backed by blob storage"""

from __future__ import annotations

from typing import ClassVar

from pydantic import (
    BaseModel,
    Field,
    field_validator,
)

from data_safe_haven.exceptions import DataSafeHavenConfigError
from data_safe_haven.functions.validators import validate_unique_list
from data_safe_haven.utility import (
    DatabaseSystem,
    LoggingSingleton,
    SoftwarePackageCategory,
)
from data_safe_haven.utility.annotated_types import (
    AzureVmSku,
    EmailAdress,
    Fqdn,
    Guid,
    IpAddress,
    TimeZone,
    UniqueList,
)

from .azure_serialisable_model import AzureSerialisableModel


class ConfigSectionAzure(BaseModel, validate_assignment=True):
    subscription_id: Guid
    tenant_id: Guid


class ConfigSectionSHM(BaseModel, validate_assignment=True):
    aad_tenant_id: Guid
    admin_email_address: EmailAdress
    admin_ip_addresses: list[IpAddress]
    fqdn: Fqdn
    timezone: TimeZone

    def update(
        self,
        *,
        aad_tenant_id: str | None = None,
        admin_email_address: str | None = None,
        admin_ip_addresses: list[str] | None = None,
        fqdn: str | None = None,
        timezone: TimeZone | None = None,
    ) -> None:
        """Update SHM settings

        Args:
            aad_tenant_id: AzureAD tenant containing users
            admin_email_address: Email address shared by all administrators
            admin_ip_addresses: List of IP addresses belonging to administrators
            fqdn: Fully-qualified domain name to use for this SHM
            timezone: Timezone in pytz format (eg. Europe/London)
        """
        logger = LoggingSingleton()
        # Set AzureAD tenant ID
        if aad_tenant_id:
            self.aad_tenant_id = aad_tenant_id
        logger.info(
            f"[bold]AzureAD tenant ID[/] will be [green]{self.aad_tenant_id}[/]."
        )
        # Set admin email address
        if admin_email_address:
            self.admin_email_address = admin_email_address
        logger.info(
            f"[bold]Admin email address[/] will be [green]{self.admin_email_address}[/]."
        )
        # Set admin IP addresses
        if admin_ip_addresses:
            self.admin_ip_addresses = admin_ip_addresses
        logger.info(
            f"[bold]IP addresses used by administrators[/] will be [green]{self.admin_ip_addresses}[/]."
        )
        # Set fully-qualified domain name
        if fqdn:
            self.fqdn = fqdn
        logger.info(
            f"[bold]Fully-qualified domain name[/] will be [green]{self.fqdn}[/]."
        )
        # Set timezone
        if timezone:
            self.timezone = timezone
        logger.info(f"[bold]Timezone[/] will be [green]{self.timezone}[/].")


class ConfigSubsectionRemoteDesktopOpts(BaseModel, validate_assignment=True):
    allow_copy: bool = False
    allow_paste: bool = False

    def update(
        self, *, allow_copy: bool | None = None, allow_paste: bool | None = None
    ) -> None:
        """Update SRE remote desktop settings

        Args:
            allow_copy: Allow/deny copying text out of the SRE
            allow_paste: Allow/deny pasting text into the SRE
        """
        # Set whether copying text out of the SRE is allowed
        if allow_copy:
            self.allow_copy = allow_copy
        LoggingSingleton().info(
            f"[bold]Copying text out of the SRE[/] will be [green]{'allowed' if self.allow_copy else 'forbidden'}[/]."
        )
        # Set whether pasting text into the SRE is allowed
        if allow_paste:
            self.allow_paste = allow_paste
        LoggingSingleton().info(
            f"[bold]Pasting text into the SRE[/] will be [green]{'allowed' if self.allow_paste else 'forbidden'}[/]."
        )


class ConfigSectionSRE(BaseModel, validate_assignment=True):
    databases: UniqueList[DatabaseSystem] = Field(
        ..., default_factory=list[DatabaseSystem]
    )
    data_provider_ip_addresses: list[IpAddress] = Field(
        ..., default_factory=list[IpAddress]
    )
    index: int = Field(..., ge=1, le=256)
    remote_desktop: ConfigSubsectionRemoteDesktopOpts = Field(
        ..., default_factory=ConfigSubsectionRemoteDesktopOpts
    )
    workspace_skus: list[AzureVmSku] = Field(..., default_factory=list[AzureVmSku])
    research_user_ip_addresses: list[IpAddress] = Field(
        ..., default_factory=list[IpAddress]
    )
    software_packages: SoftwarePackageCategory = SoftwarePackageCategory.NONE

    def update(
        self,
        *,
        data_provider_ip_addresses: list[IpAddress] | None = None,
        databases: list[DatabaseSystem] | None = None,
        workspace_skus: list[AzureVmSku] | None = None,
        software_packages: SoftwarePackageCategory | None = None,
        user_ip_addresses: list[IpAddress] | None = None,
    ) -> None:
        """Update SRE settings

        Args:
            databases: List of database systems to deploy
            data_provider_ip_addresses: List of IP addresses belonging to data providers
            workspace_skus: List of VM SKUs for workspaces
            software_packages: Whether to allow packages from external repositories
            user_ip_addresses: List of IP addresses belonging to users
        """
        logger = LoggingSingleton()
        # Set data provider IP addresses
        if data_provider_ip_addresses:
            self.data_provider_ip_addresses = data_provider_ip_addresses
        logger.info(
            f"[bold]IP addresses used by data providers[/] will be [green]{self.data_provider_ip_addresses}[/]."
        )
        # Set which databases to deploy
        if databases:
            self.databases = sorted(set(databases))
            if len(self.databases) != len(databases):
                logger.warning("Discarding duplicate values for 'database'.")
        logger.info(
            f"[bold]Databases available to users[/] will be [green]{[database.value for database in self.databases]}[/]."
        )
        # Set research desktop SKUs
        if workspace_skus:
            self.workspace_skus = workspace_skus
        logger.info(f"[bold]Workspace SKUs[/] will be [green]{self.workspace_skus}[/].")
        # Select which software packages can be installed by users
        if software_packages:
            self.software_packages = software_packages
        logger.info(
            f"[bold]Software packages[/] from [green]{self.software_packages.value}[/] sources will be installable."
        )
        # Set user IP addresses
        if user_ip_addresses:
            self.research_user_ip_addresses = user_ip_addresses
        logger.info(
            f"[bold]IP addresses used by users[/] will be [green]{self.research_user_ip_addresses}[/]."
        )


class Config(AzureSerialisableModel):
    config_type: ClassVar[str] = "Config"
    filename: ClassVar[str] = "config.yaml"
    azure: ConfigSectionAzure
    shm: ConfigSectionSHM
    sres: dict[str, ConfigSectionSRE] = Field(
        ..., default_factory=dict[str, ConfigSectionSRE]
    )

    @field_validator("sres")
    @classmethod
    def all_sre_indices_must_be_unique(
        cls, v: dict[str, ConfigSectionSRE]
    ) -> dict[str, ConfigSectionSRE]:
        indices = [s.index for s in v.values()]
        validate_unique_list(indices)
        return v

    @property
    def sre_names(self) -> list[str]:
        """Names of all SREs"""
        return list(self.sres.keys())

    def is_complete(self, *, require_sres: bool) -> bool:
        if require_sres:
            if not self.sres:
                return False
        if not all((self.azure, self.shm)):
            return False
        return True

    def sre(self, name: str) -> ConfigSectionSRE:
        """Return the config entry for this SRE, raising an exception if it does not exist"""
        if name not in self.sre_names:
            msg = f"SRE {name} does not exist"
            raise DataSafeHavenConfigError(msg)
        return self.sres[name]

    def remove_sre(self, name: str) -> None:
        """Remove SRE config section by name"""
        if name in self.sre_names:
            del self.sres[name]

    @classmethod
    def template(cls) -> Config:
        # Create object without validation to allow "replace me" prompts
        return Config.model_construct(
            azure=ConfigSectionAzure.model_construct(
                subscription_id="Azure subscription ID",
                tenant_id="Azure tenant ID",
            ),
            shm=ConfigSectionSHM.model_construct(
                aad_tenant_id="Azure Active Directory tenant ID",
                admin_email_address="Admin email address",
                admin_ip_addresses=["Admin IP addresses"],
                fqdn="TRE domain name",
                timezone="Timezone",
            ),
            sres={
                "example": ConfigSectionSRE.model_construct(
                    databases=["List of database systems to enable"],
                    data_provider_ip_addresses=["Data provider IP addresses"],
                    remote_desktop=ConfigSubsectionRemoteDesktopOpts.model_construct(
                        allow_copy="Whether to allow copying text out of the environment",
                        allow_paste="Whether to allow pasting text into the environment",
                    ),
                    workspace_skus=["Azure VM SKUs"],
                    research_user_ip_addresses=["Research user IP addresses"],
                    software_packages=SoftwarePackageCategory.ANY,
                )
            },
        )
