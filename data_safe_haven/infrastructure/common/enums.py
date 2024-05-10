from enum import UNIQUE, Enum, verify


@verify(UNIQUE)
class PermittedDomainCategories(int, Enum):
    """Categories for permitted domains."""

    ALL = 0
    APT_REPOSITORIES = 1
    AZURE_DNS_ZONES = 2
    CLAMAV_UPDATES = 3
    MICROSOFT_GRAPH_API = 4
    MICROSOFT_LOGIN = 5
    MICROSOFT_IDENTITY = 6
    SOFTWARE_REPOSITORIES_R = 7
    SOFTWARE_REPOSITORIES_PYTHON = 8
    SOFTWARE_REPOSITORIES = 9
    TIME_SERVERS = 10
    UBUNTU_KEYSERVER = 11


@verify(UNIQUE)
class FirewallPriorities(int, Enum):
    """Priorities for firewall rules."""

    # All sources: 1000-1099
    ALL = 1000
    # SHM sources: 2000-2999
    SHM_IDENTITY_SERVERS = 2000
    # SRE sources: 3000-3999
    SRE_APT_PROXY_SERVER = 3000
    SRE_GUACAMOLE_CONTAINERS = 3100
    SRE_IDENTITY_CONTAINERS = 3200
    SRE_USER_SERVICES_SOFTWARE_REPOSITORIES = 3300
    SRE_WORKSPACES = 3400


@verify(UNIQUE)
class NetworkingPriorities(int, Enum):
    """Priorities for network security group rules."""

    # Azure services: 100 - 999
    AZURE_GATEWAY_MANAGER = 100
    AZURE_LOAD_BALANCER = 200
    AZURE_PLATFORM_DNS = 300
    # SHM connections: 1000-1299
    INTERNAL_SELF = 1000
    INTERNAL_SHM_MONITORING_TOOLS = 1100
    # DNS connections: 1400-1499
    INTERNAL_SRE_DNS_SERVERS = 1400
    # SRE connections: 1500-2999
    INTERNAL_SRE_APPLICATION_GATEWAY = 1500
    INTERNAL_SRE_APT_PROXY_SERVER = 1600
    INTERNAL_SRE_DATA_CONFIGURATION = 1700
    INTERNAL_SRE_DATA_PRIVATE = 1800
    INTERNAL_SRE_GUACAMOLE_CONTAINERS = 1900
    INTERNAL_SRE_GUACAMOLE_CONTAINERS_SUPPORT = 2000
    INTERNAL_SRE_IDENTITY_CONTAINERS = 2100
    INTERNAL_SRE_USER_SERVICES_CONTAINERS = 2200
    INTERNAL_SRE_USER_SERVICES_CONTAINERS_SUPPORT = 2300
    INTERNAL_SRE_USER_SERVICES_DATABASES = 2400
    INTERNAL_SRE_USER_SERVICES_SOFTWARE_REPOSITORIES = 2500
    INTERNAL_SRE_WORKSPACES = 2600
    INTERNAL_SRE_ANY = 2999
    # Authorised external IPs: 3000-3499
    AUTHORISED_EXTERNAL_USER_IPS = 3100
    AUTHORISED_EXTERNAL_SSL_LABS_IPS = 3200
    # Wider internet: 3500-3999
    EXTERNAL_LINUX_UPDATES = 3600
    EXTERNAL_INTERNET = 3999
    # Deny all other: 4096
    ALL_OTHER = 4096


@verify(UNIQUE)
class Ports(str, Enum):
    CLAMAV = "11371"
    DNS = "53"
    HTTP = "80"
    HTTPS = "443"
    LDAP_APRICOT = "1389"
    LINUX_UPDATE = "8000"
    MSSQL = "1433"
    NEXUS = "8081"
    NTP = "123"
    POSTGRESQL = "5432"
    RDP = "3389"
    SSH = "22"
    SQUID = "3128"
