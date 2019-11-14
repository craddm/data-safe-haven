#! /bin/bash

# Load common constants and options
source ${BASH_SOURCE%/*}/configs/mirrors.sh
source ${BASH_SOURCE%/*}/configs/text.sh

# Options which are configurable at the command line
NAME_SUFFIX=""

# Document usage for this script
# ------------------------------
print_usage_and_exit() {
    echo "usage: $0 [-h] -s subscription -i shm_id [-k keyvault_name] [-r resource_group] [-t tier] [-v vnet_resource_group] [-x name_suffix]"
    echo "  -h                           display help"
    echo "  -s subscription [required]   specify subscription where the mirror servers should be deployed. (Test using 'Safe Haven Management Testing')"
    echo "  -i shm_id [required]         specify SHM ID"
    echo "  -k keyvault_name             specify name for keyvault that already contains admin passwords for the mirror servers (defaults to '${KEYVAULT_NAME}')"
    echo "  -r resource_group            specify resource group that contains the external mirror servers (defaults to '${RESOURCEGROUP}')"
    echo "  -t tier                      specify which tier these mirrors will belong to, either '2' or '3' (defaults to '${TIER}')"
    echo "  -v vnet_resource_group       specify resource group containing VNet and NSG - will be created if it does not already exist (defaults to '${VNETRESOURCEGROUP}')"
    echo "  -x name_suffix               specify (optional) suffix that will be used to distinguish these internal mirror servers from any others (defaults to '${NAME_SUFFIX}')"
    exit 1
}


# Read command line arguments, overriding defaults where necessary
# ----------------------------------------------------------------
while getopts "hi:k:r:s:t:v:x:" OPT; do
    case $OPT in
        h)
            print_usage_and_exit
            ;;
        i)
            SHMID=$OPTARG
            ;;
        k)
            KEYVAULT_NAME=$OPTARG
            ;;
        r)
            RESOURCEGROUP=$OPTARG
            ;;
        s)
            SUBSCRIPTION=$OPTARG
            ;;
        t)
            TIER=$OPTARG
            ;;
        v)
            VNETRESOURCEGROUP=$OPTARG
            ;;
        x)
            NAME_SUFFIX=$OPTARG
            ;;
        \?)
            print_usage_and_exit
            ;;
    esac
done


# Check that a subscription has been provided and switch to it
# ------------------------------------------------------------
if [ "$SUBSCRIPTION" = "" ]; then
    echo -e "${RED}Subscription is a required argument!${END}"
    print_usage_and_exit
fi
az account set --subscription "$SUBSCRIPTION" --output none


# Check that an SHM ID has been provided
# --------------------------------------
if [ "$SHMID" = "" ]; then
    echo -e "${RED}SHM ID is a required argument!${END}"
    print_usage_and_exit
fi


# Check that Tier is either 2 or 3
# --------------------------------
if [ "$TIER" != "2" ] && [ "$TIER" != "3" ]; then
    echo -e "${RED}Tier must be either '2' or '3'${END}"
    print_usage_and_exit
fi


# Set tier-dependent variables
# ----------------------------
MACHINENAME_PREFIX_EXTERNAL="${MACHINENAME_BASE}-EXTERNAL-TIER-${TIER}"
NSG_EXTERNAL="NSG_SHM_${SHMID}_PKG_MIRRORS_EXTERNAL_TIER${TIER}"
SUBNET_EXTERNAL="${SUBNET_PREFIX}_EXTERNAL_TIER${TIER}"
VNETNAME="VNET_SHM_${SHMID}_PKG_MIRRORS_TIER${TIER}"
VNET_IPTRIPLET="10.20.${TIER}"


# Set datadisk size
# -----------------
if [ "$TIER" == "2" ]; then
    PYPIDATADISKSIZE=$DATADISK_LARGE
    PYPIDATADISKSIZEGB=$DATADISK_LARGE_NGB
    CRANDATADISKSIZE=$DATADISK_MEDIUM
    CRANDATADISKSIZEGB=$DATADISK_MEDIUM_NGB
elif [ "$TIER" == "3" ]; then
    PYPIDATADISKSIZE=$DATADISK_MEDIUM
    PYPIDATADISKSIZEGB=$DATADISK_MEDIUM_NGB
    CRANDATADISKSIZE=$DATADISK_SMALL
    CRANDATADISKSIZEGB=$DATADISK_SMALL_NGB
else
    print_usage_and_exit
fi


# Setup internal names to match the external names
# ------------------------------------------------
NSG_INTERNAL="$(echo $NSG_EXTERNAL | sed 's/EXTERNAL/INTERNAL/')"
SUBNET_INTERNAL="$(echo $SUBNET_EXTERNAL | sed 's/EXTERNAL/INTERNAL/')"
MACHINENAME_PREFIX_INTERNAL="$(echo $MACHINENAME_PREFIX_EXTERNAL | sed 's/EXTERNAL/INTERNAL/')"
# Add name suffix if needed
if [ "$NAME_SUFFIX" != "" ]; then
    SUBNET_INTERNAL="${SUBNET_INTERNAL}_${NAME_SUFFIX}"
    MACHINENAME_PREFIX_INTERNAL="${MACHINENAME_PREFIX_INTERNAL}${NAME_SUFFIX}"
fi


# Ensure that the external mirrors have been set up
# -------------------------------------------------
# Ensure that resource group exists
if [ $(az group exists --name $RESOURCEGROUP) != "true" ]; then
    echo -e "${RED}Resource group ${BLUE}$RESOURCEGROUP${RED} not found! Have you deployed the external mirrors?${END}"
    print_usage_and_exit
fi

# Ensure that keyvault exists
if [ "$(az keyvault list --query '[].name' -o tsv | grep $KEYVAULT_NAME)" != "$KEYVAULT_NAME" ]; then
    echo -e "${RED}Keyvault ${BLUE}$KEYVAULT_NAME${RED} not found! Have you deployed the external mirrors?${END}"
    print_usage_and_exit
fi

# Ensure that VNet exists
if [ "$(az network vnet list --resource-group $VNETRESOURCEGROUP --query '[].name' -o tsv | grep $VNETNAME)" != "$VNETNAME" ]; then
    echo -e "${RED}VNet ${BLUE}$VNETNAME${RED} not found! Have you deployed the external mirrors?${END}"
    print_usage_and_exit
fi
IP_TRIPLET_VNET=$(az network vnet show --resource-group $VNETRESOURCEGROUP --name $VNETNAME --query "addressSpace.addressPrefixes" -o tsv | cut -d'.' -f1-3)
IP_RANGE_SBNT_EXTERNAL="${IP_TRIPLET_VNET}.0/28"

# Ensure that external NSG exists
if [ "$(az network nsg show --resource-group $VNETRESOURCEGROUP --name $NSG_EXTERNAL 2> /dev/null)" = "" ]; then
    echo -e "${RED}External NSG ${BLUE}$NSG_EXTERNAL${RED} not found! Have you deployed the external mirrors?${END}"
    print_usage_and_exit
fi

# Ensure that external subnet exists
if [ "$(az network vnet subnet list --resource-group $VNETRESOURCEGROUP --vnet-name $VNETNAME --query "[].name" -o tsv | grep 'EXTERNAL')" != "$SUBNET_EXTERNAL" ]; then
    echo -e "${RED}External subnet ${BLUE}$SUBNET_EXTERNAL${RED} not found! Have you deployed the external mirrors?${END}"
    print_usage_and_exit
fi


# Create internal NSG if it does not already exist
# ------------------------------------------------
if [ "$(az network nsg show --resource-group $VNETRESOURCEGROUP --name $NSG_INTERNAL 2> /dev/null)" = "" ]; then
    echo -e "${BOLD}Creating NSG for internal mirrors: ${BLUE}$NSG_INTERNAL${END}"
    az network nsg create --resource-group $VNETRESOURCEGROUP --name $NSG_INTERNAL --output none
    az network nsg rule create --resource-group $VNETRESOURCEGROUP --nsg-name $NSG_INTERNAL --direction Inbound --name rsyncInbound --description "Allow ports 22 and 873 for rsync" --source-address-prefixes $IP_RANGE_SBNT_EXTERNAL --destination-port-ranges 22 873 --protocol TCP --destination-address-prefixes "*" --priority 200 --output none
    az network nsg rule create --resource-group $VNETRESOURCEGROUP --nsg-name $NSG_INTERNAL --direction Inbound --name mirrorRequestsInbound --description "Allow ports 80 (http), 443 (pip) and 3128 (pip) for webservices" --source-address-prefixes VirtualNetwork --destination-port-ranges 80 443 3128 --protocol TCP --destination-address-prefixes "*" --priority 300 --output none
    az network nsg rule create --resource-group $VNETRESOURCEGROUP --nsg-name $NSG_INTERNAL --direction Inbound --name IgnoreInboundRulesBelowHere --description "Deny all other inbound" --access "Deny" --source-address-prefixes "*" --destination-port-ranges "*" --protocol "*" --destination-address-prefixes "*" --priority 3000 --output none
    az network nsg rule create --resource-group $VNETRESOURCEGROUP --nsg-name $NSG_INTERNAL --direction Outbound --name IgnoreOutboundRulesBelowHere --description "Deny all other outbound" --access "Deny" --source-address-prefixes "*" --destination-port-ranges "*" --protocol "*" --destination-address-prefixes "*" --priority 3000 --output none
fi


# Configure the internal subnet, creating it if it does not exist
# ---------------------------------------------------------------
if [ "$(az network vnet subnet show --resource-group $VNETRESOURCEGROUP --vnet-name $VNETNAME --name $SUBNET_INTERNAL --query 'name' -o tsv 2> /dev/null)" == "$SUBNET_INTERNAL" ]; then
    # Load the IP range from the internal subnet if it exists
    # -------------------------------------------------------
    IP_RANGE_SUBNET_INTERNAL=$(az network vnet subnet show --resource-group $VNETRESOURCEGROUP --vnet-name $VNETNAME --name $SUBNET_INTERNAL --query "addressPrefix" -o tsv)
else
    # Find the next valid IP range for this subnet
    # --------------------------------------------
    IP_ADDRESS_PREFIXES=$(az network vnet subnet list --resource-group $VNETRESOURCEGROUP --vnet-name $VNETNAME --query "[].addressPrefix" -o tsv)
    for FOURTH_OCTET in $(seq 0 16 240); do
        IP_RANGE_SUBNET_INTERNAL="${IP_TRIPLET_VNET}.${FOURTH_OCTET}/28"
        ALREADY_IN_USE=0
        for IP_ADDRESS_PREFIX in $IP_ADDRESS_PREFIXES; do
            if [ "$IP_RANGE_SUBNET_INTERNAL" == "$IP_ADDRESS_PREFIX" ]; then
                ALREADY_IN_USE=1
            fi
        done
        if [ $ALREADY_IN_USE -eq 0 ]; then
            break
        fi
    done
    if [ $ALREADY_IN_USE -ne 0 ]; then
        echo -e "${RED}Could not find a valid, unused IP range in ${BLUE}$VNETNAME${END}"
        print_usage_and_exit
    fi
    # ... and create the internal subnet
    # ----------------------------------
    if [ "$(az network vnet subnet show --resource-group $VNETRESOURCEGROUP --vnet-name $VNETNAME --name $SUBNET_INTERNAL --query 'name' -o tsv 2> /dev/null)" != "$SUBNET_INTERNAL" ]; then
        echo -e "${BOLD}Creating subnet ${BLUE}$SUBNET_INTERNAL${END} using the IP range ${BLUE}$IP_RANGE_SUBNET_INTERNAL${END}"
        az network vnet subnet create \
            --address-prefix $IP_RANGE_SUBNET_INTERNAL \
            --name $SUBNET_INTERNAL \
            --network-security-group $NSG_INTERNAL \
            --resource-group $VNETRESOURCEGROUP \
            --vnet-name $VNETNAME \
            --output none
    fi
fi
SUBNET_INTERNAL_ID=$(az network vnet subnet show --resource-group $VNETRESOURCEGROUP --vnet-name $VNETNAME --name $SUBNET_INTERNAL --query "id" -o tsv)
echo -e "${BOLD}Internal tier-${TIER} mirrors will be deployed in the IP range ${BLUE}$IP_RANGE_SUBNET_INTERNAL${END}"


# Configure the external NSG to allow connections to this internal IP range
# -------------------------------------------------------------------------
echo -e "${BOLD}Ensuring that NSG ${BLUE}$NSG_EXTERNAL${END}${BOLD} allows connections to IP range ${BLUE}$IP_RANGE_SUBNET_INTERNAL${END}"
# ... if rsync rules do not exist then we create them
if [ "$(az network nsg rule show --resource-group $VNETRESOURCEGROUP --nsg-name $NSG_EXTERNAL --name rsyncOutbound 2> /dev/null)" = "" ]; then
    az network nsg rule create --resource-group $VNETRESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Outbound --name rsyncOutbound --description "Allow ports 22 and 873 for rsync" --source-address-prefixes $IP_RANGE_SBNT_EXTERNAL --destination-port-ranges 22 873 --protocol TCP --destination-address-prefixes $IP_RANGE_SUBNET_INTERNAL --priority 400 --output none
# ... otherwise we update them, extracting the existing IP ranges first
else
    EXISTING_IP_RANGES=$(az network nsg rule show --resource-group $VNETRESOURCEGROUP --nsg-name $NSG_EXTERNAL --name rsyncOutbound --query "[destinationAddressPrefix, destinationAddressPrefixes]" -o tsv | xargs)
    UPDATED_IP_RANGES=$(echo $EXISTING_IP_RANGES $IP_RANGE_SUBNET_INTERNAL | tr ' ' '\n' | sort | uniq | tr '\n' ' ' | sed -e 's/ *$//')
    if [ "$UPDATED_IP_RANGES" != "$EXISTING_IP_RANGES" ]; then
        az network nsg rule update --resource-group $VNETRESOURCEGROUP --nsg-name $NSG_EXTERNAL --name rsyncOutbound --destination-address-prefixes $UPDATED_IP_RANGES --output none
    fi
fi


# Set up PyPI internal mirror
# ---------------------------
MACHINENAME_INTERNAL="PYPI-${MACHINENAME_PREFIX_INTERNAL}"
MACHINENAME_EXTERNAL="PYPI-${MACHINENAME_PREFIX_EXTERNAL}"
if [ "$(az vm show --resource-group $RESOURCEGROUP --name $MACHINENAME_INTERNAL 2> /dev/null)" != "" ]; then
    echo -e "${BOLD}VM ${BLUE}$MACHINENAME_INTERNAL${END}${BOLD} already exists in ${BLUE}$RESOURCEGROUP${END}"
else
    CLOUDINITYAML="${BASH_SOURCE%/*}/cloud-init-mirror-internal-pypi.yaml"
    ADMIN_PASSWORD_SECRET_NAME="shm-pypi-mirror-internal-tier-${TIER}-admin-password"
    if [ "$NAME_SUFFIX" != "" ]; then
        ADMIN_PASSWORD_SECRET_NAME="${ADMIN_PASSWORD_SECRET_NAME}-${NAME_SUFFIX}"
    fi

    # Construct a new cloud-init YAML file with the appropriate SSH key included
    echo -e "${BOLD}Constructing cloud-init file containing public SSH key for: ${BLUE}${MACHINENAME_EXTERNAL}${END}"
    TMPCLOUDINITYAML="$(mktemp).yaml"
    EXTERNAL_PUBLIC_SSH_KEY=$(az vm run-command invoke --name $MACHINENAME_EXTERNAL --resource-group $RESOURCEGROUP --command-id RunShellScript --scripts "cat /home/mirrordaemon/.ssh/id_rsa.pub" --query "value[0].message" -o tsv | grep "^ssh")
    az vm wait --name $MACHINENAME_EXTERNAL --resource-group $RESOURCEGROUP --updated --output none
    sed -e "s|EXTERNAL_PUBLIC_SSH_KEY|${EXTERNAL_PUBLIC_SSH_KEY}|" $CLOUDINITYAML > $TMPCLOUDINITYAML
    echo -e "${BOLD}...done.${END}"

    # Ensure that admin password is available
    if [ "$(az keyvault secret list --vault-name $KEYVAULT_NAME | grep $ADMIN_PASSWORD_SECRET_NAME)" = "" ]; then
        echo -e "${BOLD}Creating admin password for ${BLUE}$MACHINENAME_INTERNAL${END}"
        az keyvault secret set --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --value $(head /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 32) --output none
    fi
    # Retrieve admin password from keyvault
    ADMIN_PASSWORD=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --query "value" | xargs)

    # Create the VM based off the selected source image, opening port 443 for the webserver
    echo -e "${BOLD}Creating VM ${BLUE}$MACHINENAME_INTERNAL${END}${BOLD} as part of ${BLUE}$RESOURCEGROUP${END}"
    echo -e "${BOLD}This will be based off the ${BLUE}$SOURCEIMAGE${END}${BOLD} image${END}"

    # Create the data disk
    echo -e "${BOLD}Creating ${PYPIDATADISKSIZE} datadisk...${END}"
    DISKNAME=${MACHINENAME_INTERNAL}-DATA-DISK
    az disk create --resource-group $RESOURCEGROUP --name $DISKNAME --location $LOCATION --sku "Standard_LRS" --size-gb $PYPIDATADISKSIZEGB --output none

    # Find the next unused IP address in this subnet and temporarily allow outbound internet connections through the NSG from it
    PRIVATEIPADDRESS="$IP_TRIPLET_VNET.$(($(echo $IP_RANGE_SUBNET_INTERNAL | cut -d'/' -f1 | cut -d'.' -f4) + 4))"
    echo -e "${BOLD}Temporarily allowing outbound internet access from ${BLUE}$PRIVATEIPADDRESS${END}${BOLD} in NSG ${BLUE}$NSG_INTERNAL${END}${BOLD} (for use during deployment *only*)${END}"
    az network nsg rule create --resource-group $VNETRESOURCEGROUP --nsg-name $NSG_INTERNAL --direction Outbound --name configurationOutboundTemporary --description "Allow ports 80 (http), 443 (pip) and 3128 (pip) for installing software" --access "Allow" --source-address-prefixes $PRIVATEIPADDRESS --destination-port-ranges 80 443 3128 --protocol TCP --destination-address-prefixes Internet --priority 100 --output none
    az network nsg rule create --resource-group $VNETRESOURCEGROUP --nsg-name $NSG_INTERNAL --direction Outbound --name vnetOutboundTemporary --description "Block connections to the VNet" --access "Deny" --source-address-prefixes $PRIVATEIPADDRESS --destination-port-ranges "*" --protocol "*" --destination-address-prefixes VirtualNetwork --priority 200 --output none

    # Create the VM
    echo -e "${BOLD}Creating VM...${END}"
    OSDISKNAME=${MACHINENAME_INTERNAL}-OS-DISK
    az vm create \
        --admin-password $ADMIN_PASSWORD \
        --admin-username $ADMIN_USERNAME \
        --attach-data-disks $DISKNAME \
        --authentication-type password \
        --custom-data $TMPCLOUDINITYAML \
        --image $SOURCEIMAGE \
        --name $MACHINENAME_INTERNAL \
        --nsg "" \
        --os-disk-name $OSDISKNAME \
        --public-ip-address "" \
        --private-ip-address $PRIVATEIPADDRESS \
        --resource-group $RESOURCEGROUP \
        --size $MIRROR_VM_SIZE \
        --storage-sku $MIRROR_DISK_TYPE \
        --subnet $SUBNET_INTERNAL_ID \
        --output none
    rm $TMPCLOUDINITYAML
    echo -e "${BOLD}Deployed new ${BLUE}$MACHINENAME_INTERNAL${END}${BOLD} server${END}"

    # Poll VM to see whether it has finished running
    echo -e "${BOLD}Waiting for VM setup to finish (this may take several minutes)...${END}"
    az vm wait --name $MACHINENAME_INTERNAL --resource-group $RESOURCEGROUP --custom "instanceView.statuses[?code == 'PowerState/stopped'].displayStatus" --output none

    # Delete the configuration NSG rule and restart the VM
    echo -e "${BOLD}Restarting VM: ${BLUE}${MACHINENAME_INTERNAL}${END}"
    az network nsg rule delete --resource-group $VNETRESOURCEGROUP --nsg-name $NSG_INTERNAL --name configurationOutboundTemporary --output none
    az network nsg rule delete --resource-group $VNETRESOURCEGROUP --nsg-name $NSG_INTERNAL --name vnetOutboundTemporary --output none
    az vm start --resource-group $RESOURCEGROUP --name $MACHINENAME_INTERNAL --output none
    az vm wait --name $MACHINENAME_INTERNAL --resource-group $RESOURCEGROUP --custom "instanceView.statuses[?code == 'PowerState/running'].displayStatus" --output none
    echo -e "${BOLD}...done.${END}"

    # Get hostname from internal server
    echo -e "${BOLD}Getting IP address of ${BLUE}$MACHINENAME_INTERNAL${END}"
    INTERNAL_HOSTS=$(az vm run-command invoke --name ${MACHINENAME_INTERNAL} --resource-group ${RESOURCEGROUP} --command-id RunShellScript --scripts "ssh-keyscan 127.0.0.1 2> /dev/null" --query "value[0].message" -o tsv | grep "^127.0.0.1" | sed "s/127.0.0.1/${PRIVATEIPADDRESS}/")
    az vm wait --name $MACHINENAME_INTERNAL --resource-group $RESOURCEGROUP --updated --output none  # az vm run-command places the VM into 'Updating' state while running the command. The --updated flag waits for the transition from 'Updating' to 'Succeeding'
    echo -e "${BOLD}...done.${END}"

    # Update known hosts on the external server to allow connections to the internal server
    echo -e "${BOLD}Update known hosts on ${BLUE}$MACHINENAME_EXTERNAL${END}${BOLD} to allow connections to ${BLUE}$MACHINENAME_INTERNAL${END}${BOLD} (removing known_hosts.old when done)${END}"
    az vm run-command invoke --name $MACHINENAME_EXTERNAL --resource-group ${RESOURCEGROUP} --command-id RunShellScript --scripts "echo \"$INTERNAL_HOSTS\" > ~mirrordaemon/.ssh/known_hosts; ls -alh ~mirrordaemon/.ssh/; ssh-keygen -H -f ~mirrordaemon/.ssh/known_hosts 2>&1; chown mirrordaemon:mirrordaemon ~mirrordaemon/.ssh/known_hosts; rm ~mirrordaemon/.ssh/known_hosts.old; ls -alh ~mirrordaemon/.ssh/" --query "value[0].message" -o tsv
    az vm wait --name $MACHINENAME_EXTERNAL --resource-group $RESOURCEGROUP --updated --output none  # az vm run-command places the VM into 'Updating' state while running the command. The --updated flag waits for the transition from 'Updating' to 'Succeeding'
    echo -e "${BOLD}...done.${END}"

    # Update known IP addresses on the external server to schedule pushing to the internal server
    echo -e "${BOLD}Registering IP address ${BLUE}$PRIVATEIPADDRESS${END}${BOLD} with ${BLUE}$MACHINENAME_EXTERNAL${END}${BOLD} as the location of ${BLUE}$MACHINENAME_INTERNAL${END}"
    az vm run-command invoke --name $MACHINENAME_EXTERNAL --resource-group ${RESOURCEGROUP} --command-id RunShellScript --scripts "echo $PRIVATEIPADDRESS >> ~mirrordaemon/internal_mirror_ip_addresses.txt; ls -alh ~mirrordaemon/internal_mirror_ip_addresses.txt; cat ~mirrordaemon/internal_mirror_ip_addresses.txt" --query "value[0].message" -o tsv
    az vm wait --name $MACHINENAME_EXTERNAL --resource-group $RESOURCEGROUP --updated --output none  # az vm run-command places the VM into 'Updating' state while running the command. The --updated flag waits for the transition from 'Updating' to 'Succeeding'
    echo -e "${BOLD}...done.${END}"

    # Finished updating
    echo -e "${BOLD}Finished updating ${BLUE}$MACHINENAME_EXTERNAL${END}"
fi


# Set up CRAN internal mirror
# ---------------------------
if [ "$TIER" == "2" ]; then  # we do not support Tier-3 CRAN mirrors at present
    MACHINENAME_INTERNAL="CRAN-${MACHINENAME_PREFIX_INTERNAL}"
    MACHINENAME_EXTERNAL="CRAN-${MACHINENAME_PREFIX_EXTERNAL}"
    if [ "$(az vm show --resource-group $RESOURCEGROUP --name $MACHINENAME_INTERNAL 2> /dev/null)" != "" ]; then
        echo -e "${BOLD}VM ${BLUE}$MACHINENAME_INTERNAL${END}${BOLD} already exists in ${BLUE}$RESOURCEGROUP${END}"
    else
        CLOUDINITYAML="${BASH_SOURCE%/*}/cloud-init-mirror-internal-cran.yaml"
        ADMIN_PASSWORD_SECRET_NAME="shm-cran-mirror-internal-tier-${TIER}-admin-password"
        if [ "$NAME_SUFFIX" != "" ]; then
            ADMIN_PASSWORD_SECRET_NAME="${ADMIN_PASSWORD_SECRET_NAME}-${NAME_SUFFIX}"
        fi

        # Construct a new cloud-init YAML file with the appropriate SSH key included
        echo -e "${BOLD}Constructing cloud-init file containing public SSH key for: ${BLUE}${MACHINENAME_EXTERNAL}${END}"
        TMPCLOUDINITYAML="$(mktemp).yaml"
        EXTERNAL_PUBLIC_SSH_KEY=$(az vm run-command invoke --name $MACHINENAME_EXTERNAL --resource-group $RESOURCEGROUP --command-id RunShellScript --scripts "cat /home/mirrordaemon/.ssh/id_rsa.pub" --query "value[0].message" -o tsv | grep "^ssh")
        az vm wait --name $MACHINENAME_EXTERNAL --resource-group $RESOURCEGROUP --updated --output none
        sed -e "s|EXTERNAL_PUBLIC_SSH_KEY|${EXTERNAL_PUBLIC_SSH_KEY}|" $CLOUDINITYAML > $TMPCLOUDINITYAML
        echo -e "${BOLD}...done.${END}"

        # Ensure that admin password is available
        if [ "$(az keyvault secret list --vault-name $KEYVAULT_NAME | grep $ADMIN_PASSWORD_SECRET_NAME)" = "" ]; then
            echo -e "${BOLD}Creating admin password for ${BLUE}$MACHINENAME_INTERNAL${END}"
            az keyvault secret set --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --value $(head /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 32) --output none
        fi
        # Retrieve admin password from keyvault
        ADMIN_PASSWORD=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --query "value" | xargs)

        # Create the VM based off the selected source image, opening port 443 for the webserver
        echo -e "${BOLD}Creating VM ${BLUE}$MACHINENAME_INTERNAL${END}${BOLD} as part of ${BLUE}$RESOURCEGROUP${END}"
        echo -e "${BOLD}This will be based off the ${BLUE}$SOURCEIMAGE${END}${BOLD} image${END}"

        # Create the data disk
        echo -e "${BOLD}Creating $CRANDATADISKSIZE datadisk...${END}"
        DISKNAME=${MACHINENAME_INTERNAL}-DATA-DISK
        az disk create --resource-group $RESOURCEGROUP --name $DISKNAME --location $LOCATION --sku "Standard_LRS" --size-gb $CRANDATADISKSIZEGB --output none

        # Find the next unused IP address in this subnet and temporarily allow outbound internet connections through the NSG from it
        PRIVATEIPADDRESS="$IP_TRIPLET_VNET.$(($(echo $IP_RANGE_SUBNET_INTERNAL | cut -d'/' -f1 | cut -d'.' -f4) + 5))"
        echo -e "${BOLD}Temporarily allowing outbound internet access from ${BLUE}$PRIVATEIPADDRESS${END}${BOLD} in NSG ${BLUE}$NSG_INTERNAL${END}${BOLD} (for use during deployment *only*)${END}"
        az network nsg rule create --resource-group $VNETRESOURCEGROUP --nsg-name $NSG_INTERNAL --direction Outbound --name configurationOutboundTemporary --description "Allow ports 80 (http), 443 (pip) and 3128 (pip) for installing software" --access "Allow" --source-address-prefixes $PRIVATEIPADDRESS --destination-port-ranges 80 443 3128 --protocol TCP --destination-address-prefixes Internet --priority 100 --output none
        az network nsg rule create --resource-group $VNETRESOURCEGROUP --nsg-name $NSG_INTERNAL --direction Outbound --name vnetOutboundTemporary --description "Block connections to the VNet" --access "Deny" --source-address-prefixes $PRIVATEIPADDRESS --destination-port-ranges "*" --protocol "*" --destination-address-prefixes VirtualNetwork --priority 200 --output none

        # Create the VM
        echo -e "${BOLD}Creating VM...${END}"
        OSDISKNAME=${MACHINENAME_INTERNAL}-OS-DISK
        az vm create \
            --admin-password $ADMIN_PASSWORD \
            --admin-username $ADMIN_USERNAME \
            --attach-data-disks $DISKNAME \
            --authentication-type password \
            --custom-data $TMPCLOUDINITYAML \
            --image $SOURCEIMAGE \
            --name $MACHINENAME_INTERNAL \
            --nsg "" \
            --os-disk-name $OSDISKNAME \
            --public-ip-address "" \
            --private-ip-address $PRIVATEIPADDRESS \
            --resource-group $RESOURCEGROUP \
            --size $MIRROR_VM_SIZE \
            --storage-sku $MIRROR_DISK_TYPE \
            --subnet $SUBNET_INTERNAL_ID \
            --output none
        rm $TMPCLOUDINITYAML
        echo -e "${BOLD}Deployed new ${BLUE}$MACHINENAME_INTERNAL${END}${BOLD} server${END}"

        # Poll VM to see whether it has finished running
        echo -e "${BOLD}Waiting for VM setup to finish (this may take several minutes)...${END}"
        az vm wait --name $MACHINENAME_INTERNAL --resource-group $RESOURCEGROUP --custom "instanceView.statuses[?code == 'PowerState/stopped'].displayStatus" --output none

        # Delete the configuration NSG rule and restart the VM
        echo -e "${BOLD}Restarting VM: ${BLUE}${MACHINENAME_INTERNAL}${END}"
        az network nsg rule delete --resource-group $VNETRESOURCEGROUP --nsg-name $NSG_INTERNAL --name configurationOutboundTemporary --output none
        az network nsg rule delete --resource-group $VNETRESOURCEGROUP --nsg-name $NSG_INTERNAL --name vnetOutboundTemporary --output none
        az vm start --resource-group $RESOURCEGROUP --name $MACHINENAME_INTERNAL --output none
        echo -e "${BOLD}...done.${END}"

        # Get hostname from internal server
        echo -e "${BOLD}Getting IP address of ${BLUE}$MACHINENAME_INTERNAL${END}"
        INTERNAL_HOSTS=$(az vm run-command invoke --name ${MACHINENAME_INTERNAL} --resource-group ${RESOURCEGROUP} --command-id RunShellScript --scripts "ssh-keyscan 127.0.0.1 2> /dev/null" --query "value[0].message" -o tsv | grep "^127.0.0.1" | sed "s/127.0.0.1/${PRIVATEIPADDRESS}/")
        az vm wait --name $MACHINENAME_INTERNAL --resource-group $RESOURCEGROUP --updated --output none  # az vm run-command places the VM into 'Updating' state while running the command. The --updated flag waits for the transition from 'Updating' to 'Succeeding'
        echo -e "${BOLD}...done.${END}"

        # Update known hosts on the external server to allow connections to the internal server
        echo -e "${BOLD}Update known hosts on ${BLUE}$MACHINENAME_EXTERNAL${END}${BOLD} to allow connections to ${BLUE}$MACHINENAME_INTERNAL${END}${BOLD} (removing known_hosts.old when done)${END}"
        az vm run-command invoke --name $MACHINENAME_EXTERNAL --resource-group ${RESOURCEGROUP} --command-id RunShellScript --scripts "echo \"$INTERNAL_HOSTS\" > ~mirrordaemon/.ssh/known_hosts; ls -alh ~mirrordaemon/.ssh/; ssh-keygen -H -f ~mirrordaemon/.ssh/known_hosts 2>&1; chown mirrordaemon:mirrordaemon ~mirrordaemon/.ssh/known_hosts; rm ~mirrordaemon/.ssh/known_hosts.old; ls -alh ~mirrordaemon/.ssh/" --query "value[0].message" -o tsv
        az vm wait --name $MACHINENAME_EXTERNAL --resource-group $RESOURCEGROUP --updated --output none  # az vm run-command places the VM into 'Updating' state while running the command. The --updated flag waits for the transition from 'Updating' to 'Succeeding'
        echo -e "${BOLD}...done.${END}"

        # Update known IP addresses on the external server to schedule pushing to the internal server
        echo -e "${BOLD}Registering IP address ${BLUE}$PRIVATEIPADDRESS${END}${BOLD} with ${BLUE}$MACHINENAME_EXTERNAL${END}${BOLD} as the location of ${BLUE}$MACHINENAME_INTERNAL${END}"
        az vm run-command invoke --name $MACHINENAME_EXTERNAL --resource-group ${RESOURCEGROUP} --command-id RunShellScript --scripts "echo $PRIVATEIPADDRESS >> ~mirrordaemon/internal_mirror_ip_addresses.txt; ls -alh ~mirrordaemon/internal_mirror_ip_addresses.txt; cat ~mirrordaemon/internal_mirror_ip_addresses.txt" --query "value[0].message" -o tsv
        az vm wait --name $MACHINENAME_EXTERNAL --resource-group $RESOURCEGROUP --updated --output none  # az vm run-command places the VM into 'Updating' state while running the command. The --updated flag waits for the transition from 'Updating' to 'Succeeding'
        echo -e "${BOLD}...done.${END}"

        # Finished updating
        echo -e "${BOLD}Finished updating ${BLUE}$MACHINENAME_EXTERNAL${END}"
    fi
fi

