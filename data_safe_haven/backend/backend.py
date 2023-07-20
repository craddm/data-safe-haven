"""Azure backend for a Data Safe Haven deployment"""
# Standard library imports
from typing import Any, Optional

# Local imports
from data_safe_haven.config import BackendSettings, Config
from data_safe_haven.exceptions import DataSafeHavenAzureException
from data_safe_haven.external import AzureApi


class Backend:
    """Azure backend for a Data Safe Haven deployment"""

    def __init__(self, settings: BackendSettings) -> None:
        self.azure_api_: Optional[AzureApi] = None
        self.config: Config = Config(
            name=settings.name,
            subscription_name=settings.subscription_name,
        )
        # Add Azure metadata from the input settings
        self.config.azure.location = settings.location
        self.config.azure.admin_group_id = settings.admin_group_id
        self.tags = {"component": "backend"} | self.config.tags.to_dict()

    @property
    def azure_api(self) -> AzureApi:
        """Load AzureAPI on demand

        Returns:
            AzureApi: An initialised AzureApi object
        """
        if not self.azure_api_:
            self.azure_api_ = AzureApi(
                subscription_name=self.config.subscription_name,
            )
        return self.azure_api_

    def create(self) -> None:
        """Create all desired resources

        Raises:
            DataSafeHavenAzureException if any resources cannot be created
        """
        try:
            self.config.azure.subscription_id = self.azure_api.subscription_id
            self.config.azure.tenant_id = self.azure_api.tenant_id
            resource_group = self.azure_api.ensure_resource_group(
                location=self.config.azure.location,
                resource_group_name=self.config.backend.resource_group_name,
                tags=self.tags,
            )
            if not resource_group.name:
                raise DataSafeHavenAzureException(
                    f"Resource group '{self.config.backend.resource_group_name}' was not created."
                )
            identity = self.azure_api.ensure_managed_identity(
                identity_name=self.config.backend.managed_identity_name,
                location=resource_group.location,
                resource_group_name=resource_group.name,
            )
            storage_account = self.azure_api.ensure_storage_account(
                location=resource_group.location,
                resource_group_name=resource_group.name,
                storage_account_name=self.config.backend.storage_account_name,
                tags=self.tags,
            )
            if not storage_account.name:
                raise DataSafeHavenAzureException(
                    f"Storage account '{self.config.backend.storage_account_name}' was not created."
                )
            _ = self.azure_api.ensure_storage_blob_container(
                container_name=self.config.backend.storage_container_name,
                resource_group_name=resource_group.name,
                storage_account_name=storage_account.name,
            )
            _ = self.azure_api.ensure_storage_blob_container(
                container_name=self.config.pulumi.storage_container_name,
                resource_group_name=resource_group.name,
                storage_account_name=storage_account.name,
            )
            keyvault = self.azure_api.ensure_keyvault(
                admin_group_id=self.config.azure.admin_group_id,
                key_vault_name=self.config.backend.key_vault_name,
                location=resource_group.location,
                managed_identity=identity,
                resource_group_name=resource_group.name,
                tags=self.tags,
            )
            if not keyvault.name:
                raise DataSafeHavenAzureException(
                    f"Keyvault '{self.config.backend.key_vault_name}' was not created."
                )
            pulumi_encryption_key = self.azure_api.ensure_keyvault_key(
                key_name=self.config.pulumi.encryption_key_name,
                key_vault_name=keyvault.name,
            )
            self.config.pulumi.encryption_key_id = pulumi_encryption_key.id.split("/")[
                -1
            ]
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Failed to create backend resources.\n{str(exc)}"
            ) from exc

    def teardown(self) -> None:
        """Destroy all created resources

        Raises:
            DataSafeHavenAzureException if any resources cannot be destroyed
        """
        try:
            self.azure_api.remove_resource_group(
                self.config.backend.resource_group_name
            )
        except Exception as exc:
            raise DataSafeHavenAzureException(
                f"Failed to destroy backend resources.\n{str(exc)}"
            ) from exc
