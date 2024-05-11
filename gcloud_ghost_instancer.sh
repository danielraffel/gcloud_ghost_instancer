#!/bin/bash

# Function for colored text used throughout the script
color_text() {
  case $1 in
    red)    printf "\033[0;31m$2\033[0m" ;;
    green)  printf "\033[0;32m$2\033[0m" ;;
    yellow) printf "\033[0;33m$2\033[0m" ;;
    blue)   printf "\033[0;34m$2\033[0m" ;;
    *)      printf "$2" ;;
  esac
}

# Initial setup prompt
# For more information about Google Cloud Free Tier micro instances, visit: https://cloud.google.com/free/docs/free-cloud-features#free-tier-usage-limits
initial_prompt() {
  echo -e "This script will help you set up and run a Google Compute Engine E2-Micro virtual machine with https://ghost.org installed.\n\nAn E2-Micro instance has up to 1GB RAM, 30GB storage, 1TB monthly transfer, can run 24/7 and falls under Google Cloud's Always Free Tier, which means you won't incur any costs, subject to Google's terms and usage limits.\n\nLearn more: https://cloud.google.com/free/docs/free-cloud-features#free-tier-usage-limits\n"
  color_text green "\nDo you want to proceed? (Y/n): "
  read -r setup_instance

  if [ "$setup_instance" != "y" ]; then
    echo "No worries. Have a great day!"
    exit 0
  fi
}

# Check for gcloud CLI and install if not found. Installation proceeds without user interaction if found.
# For more information about Google Cloud SDK, visit: https://cloud.google.com/sdk/docs
check_gcloud_install() {
  if ! command -v gcloud &> /dev/null; then
    color_text green "gcloud SDK is required to proceed and could not be found.\nLearn more: https://cloud.google.com/sdk/docs\n\nDo you want to proceed with automatically downloading gcloud SDK and adding a shell alias? (Y/n): "
    read -r install_gcloud
    case "${install_gcloud,,}" in  # Converts to lowercase for matching
      y|yes|"")
        echo "\nInstalling gcloud..."
        curl https://sdk.cloud.google.com | bash -s -- --disable-prompts
        export PATH=$PATH:$HOME/google-cloud-sdk/bin
        source "$HOME/google-cloud-sdk/completion.bash.inc"
        echo "gcloud installed and environment initialized."
        ;;
      *)
        echo "\ngcloud is required. Exiting."
        exit 1
        ;;
    esac
  fi
}

# Function to check if gCloud is set up in either .bashrc or .zshrc
# If not found, it adds an alias for gcloud to run in shell configuration files
# After updating the files, it reloads the corresponding shell configuration
check_shell_setup() {
  if grep -q 'gcloud' ~/.bashrc || grep -q 'gcloud' ~/.zshrc; then
    :
  else
    echo "Setting up gCloud in .bashrc and .zshrc."
    echo 'export PATH=$PATH:$HOME/google-cloud-sdk/bin' >> ~/.bashrc
    echo 'export PATH=$PATH:$HOME/google-cloud-sdk/bin' >> ~/.zshrc
    source ~/.bashrc || source ~/.zshrc
  fi
}

# Function to authenticate the user, check active account, and fetch the Google Cloud Platform project ID
# Checks if a GCP project is already set in the gcloud config
# If not, it checks for active and authenticated accounts, initiates gcloud authentication if necessary
# Upon successful authentication, it fetches the newly set project ID
# Exits the script if authentication fails or no project is selected
authenticate_and_fetch_project() {
  echo "Checking for active Google Cloud account..."
  local auth_list=$(gcloud auth list --format="value(account,status)")
  local active_account=$(echo "$auth_list" | grep '*' | awk '{print $1}')

  if [[ -z "$auth_list" ]]; then
    echo "No Google Cloud accounts detected. Initiating login process..."
    gcloud auth login
    active_account=$(gcloud auth list --format="value(account,status)" | grep '*' | awk '{print $1}')
  elif [[ -z "$active_account" ]]; then
    echo "Multiple accounts are authenticated but none are set as active. Please set an active account using:"
    echo "$auth_list" | awk '{print $1}'
    echo "gcloud config set account 'ACCOUNT'"
    exit 1
  else
    echo "Active Google Cloud account: $active_account"
  fi

  PROJECT_ID=$(gcloud config get-value project 2> /dev/null)
  if [[ -z "$PROJECT_ID" ]]; then
    echo "No Google Cloud project set. Attempting to fetch project..."
    PROJECT_ID=$(gcloud config get-value project 2> /dev/null)
    if [[ -z "$PROJECT_ID" ]]; then
      echo "Authentication successful but no project selected. Exiting."
      exit 1
    fi
  fi
  echo "Using project: $PROJECT_ID"
}

# Function to prompt the user to select a Google Cloud Platform (GCP) zone for instance creation
# Display available zones that support free-tiers along with a corresponding picker to select a zone
# Prompt user to select a zone based on their geographic preference
prompt_for_zone() {
  echo -e "\nTo create a free E2-Micro instance, you'll need to setup your VM in a colocation facility that supports free-tiers."
  echo " 1) Oregon: us-west1"
  echo " 2) Iowa: us-central1"
  echo " 3) South Carolina: us-east1"
  color_text green "Select a zone that sounds like it's located closest to you (1/2/3): "
  read -r choice
  case "$choice" in
    1) ZONE="us-west1-a" ;;
    2) ZONE="us-central1-a" ;;
    3) ZONE="us-east1-a" ;;
    *) echo "\nInvalid choice. Exiting."; exit 1 ;;
  esac
  color_text yellow "\nZone set to $ZONE. Continuing...\n"
}

# Function to extract the region from a GCP zone
# Use sed to parse the region part from the full zone
get_region_from_zone() {
  REGION=$(echo $ZONE | sed 's/\(.*\)-.*/\1/')
}

# This function prompts the user to input the URL where their Ghost blog will be hosted.
# It checks for valid URL formats and confirms the URL with the user before proceeding.
# The URL must start with either 'http://' or 'https://'.
setup_url() {
  while true; do
    color_text green "\nEnter the URL where your site will be hosted (include http:// or https://): "
    read -p "" url

    # Check if URL is empty
    if [[ -z "$url" ]]; then
      echo -e "\nURL cannot be empty. Please try again."
      continue
    fi

    # Check if the URL starts with http:// or https://
    if [[ $url == http://* || $url == https://* ]]; then
      # Confirm the URL
      color_text yellow "\nYou entered: $url. Is this URL correct? (Y/n): "
      read -p "" confirmation
      if [[ "$confirmation" == "N" || "$confirmation" == "n" ]]; then
        continue
      elif [[ "$confirmation" == "Y" || "$confirmation" == "y" ]]; then
        echo -e "\nWill setup Ghost with $url. Continuing..."
        break
      else
        echo -e "\nInvalid choice. Please enter Y or N."
      fi
    else
      echo -e "\nThis is not a valid URL. Please enter a URL starting with http:// or https://."
    fi
  done
}

# This function prompts the user to enter an email address which is required for configuring letsencrypt for SSL setup.
setup_email() {
  while true; do
    color_text green "\nEnter a valid email address to register your SSL certificate with https://letsencrypt.org: "
    read -p "" email
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}$ ]]; then
      color_text yellow "\nYou entered: $email. Is this email address correct? (Y/n): "
      read -p "" confirm_email
      case "$confirm_email" in
        y|Y) echo -e "\nEmail address confirmed. Continuing...\n"; break;;
        n|N) echo -e "\nLet's try again."; continue;;
        *) echo -e "\nInvalid choice. Please enter Y or N.";;
      esac
    else
      echo -e "\nThis is not a valid email address. Please enter a valid email."
    fi
  done
}

# This function configures the Mailgun settings for sending emails through Ghost.
# It gives the user the option to set up Mailgun and collects necessary credentials.
# The function also lets the user choose the Mailgun SMTP host and confirms the choices before saving.
setup_mailgun() {
  color_text green "Do you want to setup Ghost to send emails using Mailgun? (Y/n): "
  read -p "" setup_choice

  case "${setup_choice,,}" in
    n|no)
      return
      ;;
  esac

  color_text green "Have you already set up your mailgun.com account? (Y/n):\n"
  read -p "" account_choice

  case "${account_choice,,}" in
    n|no)
      return
      ;;
  esac

  while true; do
    color_text green "Enter your mailgun username:\n"
    read -p "" mailgun_username
    read -p "You entered: $mailgun_username. Is this correct? (Y/n): " username_confirm
    case "${username_confirm,,}" in
      y|yes|"")
        break
        ;;
    esac
  done

  while true; do
    color_text green "Enter your mailgun password:\n"
    read -p "" mailgun_password
    read -p "You entered: $mailgun_password. Is this correct? (Y/n): " password_confirm
    case "${password_confirm,,}" in
      y|yes|"")
        break
        ;;
    esac
  done

  while true; do
    echo "Select which Mailgun SMTP host you're using:"
    echo "1) smtp.mailgun.org (default)"
    echo "2) smtp.eu.mailgun.org"
    color_text green "Pick by entering the number (1/2):\n"
    read -p "" smtp_choice

    case $smtp_choice in
      1|"") smtp_mailgun="smtp.mailgun.org"; break;;
      2) smtp_mailgun="smtp.eu.mailgun.org"; break;;
      *) echo "Invalid choice. Please try again.";;
    esac
  done
  
  setup_mail="--mail SMTP --mailservice Mailgun --mailuser $mailgun_username --mailpass $mailgun_password --mailhost $smtp_mailgun --mailport 2525"
  echo "Ghost will be configured with these Mailgun SMTP settings:\n$setup_mail"
}

# This function is responsible for naming the Google Cloud VM instance.
# It allows for customization of the instance name and ensures that the chosen name adheres to GCP naming rules.
# Additionally, it checks for existing instances with the same name to avoid naming conflicts.
name_instance() {
  while true; do
    # Asks the user if they want to customize the VM name prefix.
    printf "\nThis script will create a VM named 'ghost' you have the option to add a custom prefix (eg daniel-ghost)\n"
    read -r -p "$(color_text green "\nDo you want to add a customize prefix to your VM? (Y/n):") " CUSTOMIZE

    case "${CUSTOMIZE,,}" in  # Convert to lowercase
      y|yes|"")
        # Prompts for a custom VM name prefix if customization is desired.
        read -r -p "$(color_text green "\nCustomize the prefix for your VM (e.g. 'yourprefix-ghost'):") " CUSTOM_NAME
        ;;
      n|no)
        # Uses the default 'ghost' if no customization is desired.
        CUSTOM_NAME=""
        ;;
      *)
        # Ask again if input is not recognized.
        color_text red "Invalid input. Please answer with Y/n."
        continue
        ;;
    esac

    # The full VM name will be in the format <CUSTOM_NAME>-ghost.
    if [[ -z "$CUSTOM_NAME" ]]; then
      INSTANCE_NAME="ghost"
    else
      # Adjusts the name to conform to GCP VM naming rules.
      ORIGINAL_NAME="$CUSTOM_NAME"
      CUSTOM_NAME=$(echo "$CUSTOM_NAME" | tr '[:upper:]' '[:lower:]')
      CUSTOM_NAME=${CUSTOM_NAME:0:62}
      CUSTOM_NAME=$(echo "$CUSTOM_NAME" | sed 's/[^a-z0-9-]//g')
      CUSTOM_NAME=$(echo "$CUSTOM_NAME" | sed 's/^-//;s/-*$//')
      INSTANCE_NAME="${CUSTOM_NAME}-ghost"
    fi

    # Informs the user if any adjustments were made to the name due to GCP rules.
    if [[ "$ORIGINAL_NAME" != "$CUSTOM_NAME" && -n "$ORIGINAL_NAME" ]]; then
      green_text "\nName adjusted to '$INSTANCE_NAME' due to GCP rules. Is this OK?"
      read -r -p $'\e[92m(Y/n):\e[0m ' CONFIRM
      case "${CONFIRM,,}" in
        n|no)
          continue
          ;;
      esac
    fi

    # Checks if the VM name already exists in the project; if so, prompts for a new name.
    EXISTING_INSTANCE=$(gcloud compute instances list --filter="name=($INSTANCE_NAME)" --format="get(name)")
    if [[ "$EXISTING_INSTANCE" == "$INSTANCE_NAME" ]]; then
      color_text green "\nName '$INSTANCE_NAME' already exists. Choose another."
      continue
    fi

    # Once a unique and GCP-compliant name is confirmed, informs the user of the final VM name.
    color_text green "\nYour VM will be named: $INSTANCE_NAME"
    color_text yellow "\n\nThis free tier is limited, ignore the WARNING you're about to see that you have selected a disk size of under [200GB] which may result in poor I/O performance.\n"
    color_text yellow "\nYou can also ignore the WARNING that your disk size: '30 GB' is larger than image size: '10 GB'. Ubuntu will automatically resize itself to use all the 30 GB you've allocated during the first boot.\n\n"
    break
  done
}

# This function performs necessary setup before creating a GCP instance.
# It sets up the Google Cloud project ID, fetches the default service account email,
# updates IAM roles, and prepares the region and zone information.
# Additionally, it retrieves stored passwords for the root and service accounts from Google Cloud Secret Manager.
prepare_instance_environment() {
  # Get the Project ID where the secret should reside
  SECRET_PROJECT_ID=$(gcloud config get-value project)

  # Fetch the Compute Engine default service account email and store it in a variable
  SERVICE_ACCOUNT_EMAIL=$(gcloud iam service-accounts list --format='value(email)' --filter='displayName:"Compute Engine default service account"')

  # Update the IAM role for the Compute Engine default service account
  gcloud secrets add-iam-policy-binding service-account-password-$INSTANCE_NAME \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="roles/secretmanager.secretAccessor"

  # Assume ZONE is already selected by the user and is a global variable
  REGION=$(echo $ZONE | sed 's/\(.*\)-.*/\1/')  # Set REGION based on ZONE

  # Fetch passwords from Google Cloud Secret Manager using the Project ID variable
  ROOT_PASSWORD=$(gcloud secrets versions access latest --secret="root-password-$INSTANCE_NAME" --project=$SECRET_PROJECT_ID)
  SERVICE_ACCOUNT_PASSWORD=$(gcloud secrets versions access latest --secret="service-account-password-$INSTANCE_NAME" --project=$SECRET_PROJECT_ID)
}

# Function to create a Standard tier static IP address
create_static_ip() {
  # Assign a name to the static IP
  STATIC_IP_NAME="$INSTANCE_NAME-ip"

  # Create a Standard tier static IP address
  gcloud compute addresses create $STATIC_IP_NAME --region=$REGION --network-tier=STANDARD

  # Get the static IP address
  STATIC_IP=$(gcloud compute addresses describe $STATIC_IP_NAME --region=$REGION --format='get(address)')
}

  # Retrieve MySQL password from Google Secret Manager
  # Check for existing firewall rule for SMTP port 2525, create if not found
  # Create Google Cloud Compute Engine instance with specified parameters
  # - Machine type: e2-medium
  # - Disk size: 30GB
  # - Operating System: Ubuntu 22.04
  # - Network Tags: Mail, custom name for HTTP and HTTPS firewall rules
  # Initialize instance with a startup script to configure users, permissions, and SSH keys
  # Loop until SSH is available on the new instance, then exit
create_instance() {
    # Retrieve the secret from Google Secret Manager
    mysql_password=$(gcloud secrets versions access latest --secret="$secret_name")

    # Check if the firewall rule for sending email exists
    if gcloud compute firewall-rules describe allow-outgoing-2525 &>/dev/null; then
        echo "\nFirewall rule allow-outgoing-2525 already exists."
    else
        # Create the firewall rule
        gcloud compute firewall-rules create allow-outgoing-2525 \
            --direction=EGRESS \
            --network=default \
            --action=ALLOW \
            --rules=tcp:2525 \
            --destination-ranges=0.0.0.0/0 \
            --target-tags=mail
    fi

    # Create a Google Cloud Compute Engine instance with specified parameters
    gcloud compute instances create $INSTANCE_NAME \
        --zone=$ZONE \
        --machine-type=e2-medium \
        --image-project=ubuntu-os-cloud \
        --image-family=ubuntu-2204-lts \
        --boot-disk-size=30GB \
        --boot-disk-type=pd-standard \
        --tags=mail,http-server,https-server \
        --no-shielded-secure-boot \
        --no-shielded-vtpm \
        --no-shielded-integrity-monitoring \
        --scopes=https://www.googleapis.com/auth/cloud-platform \
        --service-account service-account@$PROJECT_ID.iam.gserviceaccount.com \
        --metadata-from-file ssh-keys-for-root=$HOME/.ssh/root_key-${INSTANCE_NAME}.pub,ssh-keys-for-service-account=$HOME/.ssh/service_account_key-${INSTANCE_NAME}.pub \
        --network-tier=STANDARD \
        --address=$STATIC_IP \
        --metadata startup-script='#!/bin/bash
        # Configuring Passwordless sudo for service-account
        echo "service-account ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/service-account
        chmod 0440 /etc/sudoers.d/service-account
        # Variables
        INSTANCE_NAME=$(curl -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/name")
        PROJECT_ID=$(curl -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/project/project-id")

        # Set root password
        ROOT_PASSWORD=$(gcloud secrets versions access latest --secret="root-password-${INSTANCE_NAME}" --project=${PROJECT_ID})
        echo "root:${ROOT_PASSWORD}" | chpasswd

        # Create and set service-account password
        SERVICE_ACCOUNT_PASSWORD=$(gcloud secrets versions access latest --secret="service-account-password-${INSTANCE_NAME}" --project=${PROJECT_ID})
        useradd service-account
        echo "service-account:${SERVICE_ACCOUNT_PASSWORD}" | chpasswd
        usermod -aG sudo service-account

        # Make sure .ssh directories exist
        mkdir -p /root/.ssh
        mkdir -p /home/service-account/.ssh
        chown service-account:service-account /home/service-account/.ssh

        # Set correct ownership and permissions for /home/service-account
        chown -R service-account:service-account /home/service-account
        chmod 755 /home/service-account

        # Add authorized keys
        echo "$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/ssh-keys-for-root)" >> /root/.ssh/authorized_keys
        echo "$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/ssh-keys-for-service-account)" >> /home/service-account/.ssh/authorized_keys
        '

    # Retrieve the instance IP
    INSTANCE_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
    echo "Your VM is ready BUT before proceeding..."
    color_text yellow "Update your DNS settings to point $url to $STATIC_IP.\n"
    echo -n "After updating, press Enter to continue..."
    read -r

    # Loop until SSH is available for the Google Cloud Compute instance
    until gcloud compute ssh $INSTANCE_NAME --zone $ZONE --command "echo connected" &> /dev/null
    do
        echo "Waiting for SSH to be available..."
        sleep 5
    done
    echo "SSH is now available."
}

# This function handles SSHing into the Google Cloud instance and executing a remote script.
# It performs retries up to a maximum limit if the SSH connection or remote script execution fails.
# Additionally, it clears and loads the appropriate SSH keys to avoid conflicts and sets the SSH options to skip host key verification.
ssh_instance() {
    # Get the IP for the instance
    INSTANCE_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

    # Add the server's host key to the local known_hosts file
    ssh-keyscan -H $INSTANCE_IP >> $HOME/.ssh/known_hosts

    # Clear all loaded keys
    ssh-add -D

    # Load only the necessary keys
    ssh-add $HOME/.ssh/service_account_key-${INSTANCE_NAME}

    # Time to wait before retrying SSH
    WAIT_TIME_SECONDS=5

    # Maximum total retries
    MAX_TOTAL_RETRIES=20
    TOTAL_RETRIES=0

    while true; do
      if [ $TOTAL_RETRIES -ge $MAX_TOTAL_RETRIES ]; then
        echo "Maximum total retries reached, exiting..."
        exit 1
      fi

# Execute SSH to connect to the instance, passing various options and key file
# Utilize a "here document" to execute multiple commands after SSH login

# - 'ssh -t': Force pseudo-terminal allocation, often used when running an interactive application
# - 'IdentitiesOnly=yes': Specifies that ssh should only use the authentication identity files configured, ignoring other default files
# - 'StrictHostKeyChecking=no': Automatically adds new host keys to the user's known hosts files

# Inside the SSH session, the following tasks are performed:
# 1) Open a new 'screen' session named 'ghost_install'
# 2) Download a shell script that installs Ghost from a GitHub repository
# 3) Make the downloaded script executable
# 4) Execute the script
ssh -t -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -i $HOME/.ssh/service_account_key-${INSTANCE_NAME} service-account@$INSTANCE_IP <<ENDSSH
export SERVICE_ACCOUNT_PASSWORD="\$(gcloud secrets versions access latest --secret="service-account-password-$INSTANCE_NAME")"
screen -S ghost_install
mkdir -p /tmp/ghost_install
cd /tmp/ghost_install
curl -O https://raw.githubusercontent.com/danielraffel/gcloud_ghost_instancer/main/install_on_server.sh
chmod +x install_on_server.sh
INSTANCE_NAME="$INSTANCE_NAME" bash -x ./install_on_server.sh
ENDSSH

      SSH_EXIT_CODE=$?

      if [ $SSH_EXIT_CODE -eq 0 ]; then
        echo "SSH connection and script execution successful."
        break
      else
        echo "SSH connection or script execution failed. Waiting for $WAIT_TIME_SECONDS seconds before retrying..."
        ssh-keygen -R $INSTANCE_IP
        sleep $WAIT_TIME_SECONDS
      fi

      TOTAL_RETRIES=$((TOTAL_RETRIES + 1))
    done
}

# This function checks if Google Cloud Secret Manager is enabled for the project.
# If not, it enables the service and waits until the service is active.
# Secret Manager is used to store passwords in a secure location that can be accessed on the remote machine.
check_and_enable_secret_manager() {
  # Check if Secret Manager is enabled
  if gcloud services list --enabled | grep -q 'secretmanager.googleapis.com'; then
    echo "Secret Manager is already enabled. This script will use Secret Manager to securely store passwords in your account."
  else
    # Inform the user
    echo "Secret Manager is not enabled. Enabling now, this might take a moment..."

    # Enable the service
    gcloud services enable secretmanager.googleapis.com

    # Wait and check until the service is enabled
    until gcloud services list --enabled | grep -q 'secretmanager.googleapis.com'; do
      sleep 5  # wait for 5 seconds before checking again
    done

    echo "Secret Manager is now enabled. This script will use Secret Manager to securely store passwords in your account."
  fi
}

# This function generates a secure 32-character password using OpenSSL.
# It then creates a unique secret name by appending the password's intended use and the VM instance name.
# The generated password is stored in Google Cloud's Secret Manager under the generated secret name.
# If needed, the function can overwrite an existing secret instead of creating a new one.
generate_and_store_password() {
    # Generate a secure 32-character password
    password=$(openssl rand -base64 32)

    # Create a secret name based on the type and instance name
    secret_name="$1-password-$INSTANCE_NAME"

    # Check if the secret already exists
    if gcloud secrets describe "$secret_name" >/dev/null 2>&1; then
        # Secret exists, add a new version
        version_info=$(printf "%s" "$password" | gcloud secrets versions add "$secret_name" --data-file=- --format="value(name)")
        latest_version=$(echo "$version_info" | awk -F'/' '{print $NF}')

        echo "Password updated for $secret_name with new version $version_info"

        # Retrieve all versions of the secret
        versions=$(gcloud secrets versions list "$secret_name" --format="value(name)")

        # Iterate over the versions and destroy the older ones
        for version in $versions; do
            version_number=$(echo "$version" | awk -F'/' '{print $NF}')
            if [[ "$version_number" != "$latest_version" ]]; then
                gcloud secrets versions destroy "$version_number" --secret="$secret_name" --quiet
                echo "Deleted older version $version_number of secret $secret_name"
            fi
        done
    else
        # Secret doesn't exist, create a new one
        gcloud secrets create "$secret_name" --data-file=- <<< "$password"
        echo "Password generated and stored as $secret_name"
    fi
}

# This function prepares and stores the setup parameters needed for installing Ghost.
# It initializes ghost_install_setup_parameters with the URL provided.
# If setup_mail is defined and non-empty, it appends these mail setup parameters to ghost_install_setup_parameters.
# Finally, this concatenated string is saved as a Google Cloud secret, allowing it to be securely accessed later on the server.
custom_ghost_setup_parameters() {
    # Prepare the project name by replacing dots and slashes from the URL
    pname=$(echo "$url" | sed 's/https:\/\///;s/http:\/\///;s/\./-/g')
    
    # Initialize ghost_install_setup_parameters with URL
    local ghost_install_setup_parameters="--url $url --sslemail $email --pname $pname --log file"

    # Check if setup_mail exists and has content, if so append to ghost_install_setup_parameters
    if [ -n "$setup_mail" ]; then
        ghost_install_setup_parameters="$ghost_install_setup_parameters $setup_mail"
    fi

    # Define the secret name
    secret_name="ghost_install_setup_parameters-$INSTANCE_NAME"

    # Check if the secret already exists
    if gcloud secrets describe "$secret_name" >/dev/null 2>&1; then
        # Secret exists, add a new version
        version_info=$(printf "%s" "$ghost_install_setup_parameters" | gcloud secrets versions add "$secret_name" --data-file=- --format="value(name)")
        latest_version=$(echo "$version_info" | awk -F'/' '{print $NF}')

        echo "Updated $secret_name with new version $version_info"

        # Retrieve all versions of the secret
        versions=$(gcloud secrets versions list "$secret_name" --format="value(name)")

        # Iterate over the versions and destroy the older ones
        for version in $versions; do
            version_number=$(echo "$version" | awk -F'/' '{print $NF}')
            if [[ "$version_number" != "$latest_version" ]]; then
                gcloud secrets versions destroy "$version_number" --secret="$secret_name" --quiet
                echo "Deleted older version $version_number of secret $secret_name"
            fi
        done
    else
        # Secret doesn't exist, create a new one
        gcloud secrets create "$secret_name" --data-file=- <<< "$ghost_install_setup_parameters"
        echo "Password generated and stored as $secret_name"
    fi
}

# This function is responsible for generating SSH keys, creating a GCP service account, and storing certain variables for later use.
# It begins by generating SSH keys for the root and service-account users in the .ssh directory.
# It fetches the default service account email for the Compute Engine and stores it in a variable.
# A new service account is then created and assigned the role of secretAccessor.
# The IAM role of the default service account is also updated to enable access to Secret Manager.
# Finally, key setup variables like INSTANCE_NAME, ZONE, and REGION are saved to a temporary file for later use in other functions like downgrade_instance.
create_keys() { 
  # Generate SSH keys for root and service-account in the ssh directory
  ssh-keygen -t rsa -b 4096 -C "root" -f "$HOME/.ssh/root_key-${INSTANCE_NAME}"
  ssh-keygen -t rsa -b 4096 -C "service-account" -f "$HOME/.ssh/service_account_key-${INSTANCE_NAME}"

  # Fetch the Compute Engine default service account email and store it in a variable
  SERVICE_ACCOUNT_EMAIL=$(gcloud iam service-accounts list --format='value(email)' --filter='displayName:"Compute Engine default service account"')

  # Create GCP service account
  gcloud iam service-accounts create service-account --display-name "service-account"

  # Grant necessary roles to the service account
  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member serviceAccount:service-account@$PROJECT_ID.iam.gserviceaccount.com \
    --role roles/secretmanager.secretAccessor

  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member serviceAccount:service-account@$PROJECT_ID.iam.gserviceaccount.com \
    --role roles/compute.instanceAdmin.v1

  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member serviceAccount:service-account@$PROJECT_ID.iam.gserviceaccount.com \
    --role roles/compute.osLogin

  gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member serviceAccount:service-account@$PROJECT_ID.iam.gserviceaccount.com \
    --role roles/iam.serviceAccountUser

  # Update the IAM role for the Compute Engine default service account
  gcloud secrets add-iam-policy-binding service-account-password-$INSTANCE_NAME \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="roles/secretmanager.secretAccessor"

  # Write setup variables to a file for use when resizing the instance in downgrade_instance
  echo "INSTANCE_NAME=$INSTANCE_NAME" > $HOME/temp_vars.sh
  echo "ZONE=$ZONE" >> $HOME/temp_vars.sh
  echo "REGION=$REGION" >> $HOME/temp_vars.sh
}

# This function performs several actions to downgrade a Google Cloud Platform (GCP) VM instance from e2-medium to e2-micro.
# It starts by stopping the existing e2-medium instance, switches its machine type to e2-micro, and then restarts it.
# Additionally, it creates a Standard tier static IP address and associates it with the restarted instance.
# Finally, it cleans up any temporary variables and initiates an SSH session into the new machine.
downgrade_instance() {
  # Source the variables from temp_vars.sh to complete the next few commands since they are no longer in memory
  source $HOME/temp_vars.sh

  # Get the name of the access config for the instance
  INSTANCE_ACCESS_CONFIG=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].name)')

  # stop the e2-medium instance
  gcloud compute instances stop $INSTANCE_NAME --zone=$ZONE

  # change the machine type from e2-medium to e2-micro
  gcloud compute instances set-machine-type $INSTANCE_NAME --zone=$ZONE --machine-type=e2-micro

  # Remove any existing external IP from micro-instance
  gcloud compute instances delete-access-config $INSTANCE_NAME --zone=$ZONE --access-config-name="$INSTANCE_ACCESS_CONFIG"

  # Attach the static IP
  gcloud compute instances add-access-config $INSTANCE_NAME --zone=$ZONE --access-config-name="$STATIC_IP_NAME" --address=$STATIC_IP --network-tier=STANDARD

  # start the e2-micro
  gcloud compute instances start $INSTANCE_NAME --zone=$ZONE

  # Delete the temporary variables file
  rm $HOME/temp_vars.sh

  # SSH into the remote machine
  # ssh -t -i $HOME/.ssh/service_account_key-${INSTANCE_NAME} service-account@$INSTANCE_IP 'ghost ls; exit'

  # Share machine IP address
  color_text green "\nYour VM is now running at: $STATIC_IP\n"

  # Provide the user with the SSH command to manually connect to the instance
  color_text yellow "\nTo manually SSH into your instance in the future, run the following command:\n"
  color_text blue "ssh -i ~/.ssh/service_account_key-$INSTANCE_NAME service-account@$STATIC_IP\n"

  # Provide the user with info if the SSH key won't work
  color_text yellow "\nIf you get an error when you SSH don't worry just run this command and then try to SSH in again:\n"
  color_text blue "ssh-keygen -R $STATIC_IP\n"

  # Add the static IP address to Known Hosts file
  ssh-keyscan -H $STATIC_IP >> $HOME/.ssh/known_hosts

  # Initialize a counter to keep track of elapsed time
  counter=0

  # Loop to check if SSH is available on the specified IP and port
  while true; do
    nc -z -w5 $STATIC_IP 22 && break  # Check if port 22 is open on the static IP
    echo "Waiting for SSH to be available..."
    sleep 5  # Wait for 5 seconds before checking again
    
    # Increment counter by 5 to account for the 5-second sleep
    let counter=counter+5

    # Break out of the loop if 90 seconds have passed without a successful connection
    if [ $counter -ge 90 ]; then
      echo "Timed out waiting for SSH."
      break
    fi
  done

  # SSH into the remote machine at the static address
  ssh -t -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -i $HOME/.ssh/service_account_key-${INSTANCE_NAME} service-account@$STATIC_IP << "ENDSSH"
  # Open a screen session
  screen -S ghost_install
  cd /var/www/ghost
  ghost ls
ENDSSH
}

# Optional debug function used during development.
# Assumes you've run the script and setup a server with keys and want to access a hardcoded VM IP and jump directly into ssh_instance.
# To run execute "sh gcloud_ghost_instancer.sh debug_vm" 
debug_vm() {
    INSTANCE_NAME="yourprefix-ghost"
    ZONE="us-west1-a"

  # Get the IP for the instance
  INSTANCE_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

  # SSH into the remote machine
  ssh -t -i ~/.ssh/gcp yourname@$INSTANCE_IP << "ENDSSH"
  journalctl -f
ENDSSH
}

# Main function that orchestrates script behavior
  main() {
    # Check if the first argument is "debug_vm" and if so, run the debug_vm function
    if [ "$1" == "debug_vm" ]; then
      debug_vm
      setup_vm_instance
      exit 0
    fi

    initial_prompt
    check_gcloud_install
    check_shell_setup
    authenticate_and_fetch_project
    prompt_for_zone
    get_region_from_zone
    setup_url
    setup_email
    setup_mailgun
    name_instance
    check_and_enable_secret_manager
    generate_and_store_password "root"
    generate_and_store_password "service-account"
    generate_and_store_password "mysql"
    custom_ghost_setup_parameters
    create_keys
    create_static_ip
    create_instance
    ssh_instance
    downgrade_instance
}

main "$@"
