from enum import UNIQUE, Enum, verify


@verify(UNIQUE)
class FirewallPriorities(int, Enum):
    """Priorities for firewall rules."""

    # All sources: 1000-1099
    ALL = 1000
    # SHM sources: 2000-2999
    SHM_IDENTITY_SERVERS = 2000
    SHM_UPDATE_SERVERS = 2100
    # SRE sources: 3000-3999
    SRE_GUACAMOLE_CONTAINERS = 3000
    SRE_IDENTITY_CONTAINERS = 3100
    SRE_USER_SERVICES_SOFTWARE_REPOSITORIES = 3200
    SRE_WORKSPACES = 3300


@verify(UNIQUE)
class NetworkingPriorities(int, Enum):
    """Priorities for network security group rules."""

    # Azure services: 0 - 999
    AZURE_CLOUD = 100
    AZURE_GATEWAY_MANAGER = 200
    AZURE_LOAD_BALANCER = 300
    AZURE_PLATFORM_DNS = 400
    # SHM connections: 1000-1399
    INTERNAL_SELF = 1000
    INTERNAL_SHM_BASTION = 1100
    INTERNAL_SHM_LDAP_TCP = 1200
    INTERNAL_SHM_LDAP_UDP = 1250
    INTERNAL_SHM_MONITORING_TOOLS = 1300
    INTERNAL_SHM_UPDATE_SERVERS = 1400
    # DNS connections: 1400-1499
    INTERNAL_SRE_DNS_SERVERS = 1499
    # SRE connections: 1500-2999
    INTERNAL_SRE_APPLICATION_GATEWAY = 1500
    INTERNAL_SRE_DATA_CONFIGURATION = 1600
    INTERNAL_SRE_DATA_PRIVATE = 1700
    INTERNAL_SRE_GUACAMOLE_CONTAINERS = 1800
    INTERNAL_SRE_GUACAMOLE_CONTAINERS_SUPPORT = 1900
    INTERNAL_SRE_IDENTITY_CONTAINERS = 1950
    INTERNAL_SRE_USER_SERVICES_CONTAINERS = 2000
    INTERNAL_SRE_USER_SERVICES_CONTAINERS_SUPPORT = 2100
    INTERNAL_SRE_USER_SERVICES_DATABASES = 2200
    INTERNAL_SRE_USER_SERVICES_SOFTWARE_REPOSITORIES = 2300
    INTERNAL_SRE_WORKSPACES = 2400
    INTERNAL_SRE_ANY = 2999
    # Authorised external IPs: 3000-3499
    AUTHORISED_EXTERNAL_ADMIN_IPS = 3000
    AUTHORISED_EXTERNAL_USER_IPS = 3100
    AUTHORISED_EXTERNAL_SSL_LABS_IPS = 3200
    # Wider internet: 3500-3999
    EXTERNAL_LINUX_UPDATES = 3600
    EXTERNAL_INTERNET = 3999
    # Deny all other: 4096
    ALL_OTHER = 4096
