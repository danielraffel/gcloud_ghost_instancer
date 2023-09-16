#!/bin/bash

install_ghost_dependencies() {
    #Install Nginx and open the firewall
    sudo apt install -y nginx && sudo ufw allow 'Nginx Full'

    #Install NodeJS
    sudo apt update
    sudo apt install -y ca-certificates curl gnupg
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    NODE_MAJOR=18
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
    sudo apt update
    sudo apt install nodejs -y
    sudo npm install -g npm@latest

    #Install MySQL
    sudo apt install -y mysql-server

    #Clean up
    sudo apt -y autoremove

    #Start MySQL in modified mode
    sudo systemctl set-environment MYSQLD_OPTS="--skip-networking --skip-grant-tables"
    sudo systemctl start mysql.service

    # Set the instance name 
    INSTANCE_NAME=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name)

    # Get the current instance's zone
    ZONE=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/zone" -H "Metadata-Flavor: Google" | awk -F '/' '{print $4}')

    # Get the IP for the instance
    # INSTANCE_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
    INSTANCE_IP=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip" -H "Metadata-Flavor: Google")


    # Retrieve MySQL Password from Google Secret Manager
    # Define the secret name
    secret_name="mysql-password-$INSTANCE_NAME"

    # Retrieve the secret from Google Secret Manager
    mysql_password=$(gcloud secrets versions access latest --secret="$secret_name")

    if [ -z "$mysql_password" ]; then
    echo "Failed to retrieve MySQL password from Secret Manager."
    exit 1
    fi

    # Create a MySQL Commands File
    # Create a temporary SQL file
    sql_file=$(mktemp)

    if [ -z "$sql_file" ]; then
    echo "Failed to create a temporary SQL file."
    exit 1
    fi

    # Add MySQL commands to the file
    cat <<EOF > "$sql_file"
    FLUSH PRIVILEGES;
    USE mysql;
    ALTER USER 'root'@'localhost' IDENTIFIED BY '$mysql_password';
EOF

    # Execute MySQL commands
    sudo mysql -u root < "$sql_file"

    # Clean up the temporary SQL file
    rm -f "$sql_file"

    # Restart MySQL and switch to production mode. Run
    sudo systemctl unset-environment MYSQLD_OPTS
    sudo systemctl revert mysql
    sudo killall -u mysql
    sudo systemctl restart mysql.service
    
    # Configure MySQL as follows to avoid sudo mysql_secure_installation which is interactive and requires a user to enter details
    # By default, MySQL may have the validate_password plugin enabled, which enforces password strength policies
#    sudo mysql -uroot -p$mysql_password -e "UNINSTALL PLUGIN validate_password;"
    # Remove the anonymous user accounts, which can be a security risk if left in the MySQL database
#    sudo mysql -uroot -p$mysql_password -e "DROP USER ''@'localhost'"
    # Allow Root Login Remotely -- don't think we need to do this
    # mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH 'mysql_native_password' BY 'your_password';"
    # Because our hostname varies we'll use some Bash magic here.
#    sudo mysql -uroot -p$mysql_password -e "DROP USER ''@'$(hostname)'"
    # Drops the 'test' database, which is a default database that may not be needed in a production environment
#    sudo mysql -uroot -p$mysql_password -e "DROP DATABASE test"
#    # Reloads the privilege tables, ensuring that the changes made to user accounts and databases take effect immediately
#    sudo mysql -uroot -p$mysql_password -e "FLUSH PRIVILEGES"

    # # Turn off MySQL’s performance schema to reduce its memory usage
    # # Using echo and tee to add configuration to my.cnf
    # # echo "[mysqld]" > "$mysql_config_file"
    # # echo "performance_schema=0" >> "$mysql_config_file"
    # echo "[mysqld]" | sudo tee "$mysql_config_file"
    # echo "performance_schema=0" | sudo tee -a "$mysql_config_file"

    # #Restart MySQL and log in:
    # sudo /etc/init.d/mysql restart

    # # Add MySQL root user and password to the configuration file to make it easy to access at the command line
    # # echo "[client]" > "$mysql_config_file"
    # # echo "user=root" >> "$mysql_config_file"
    # # echo "password=$mysql_password" >> "$mysql_config_file"
    # echo "[client]" | sudo tee "$mysql_config_file"
    # echo "user=root" | sudo tee -a "$mysql_config_file"
    # echo "password=$mysql_password" | sudo tee -a "$mysql_config_file"

    # Define the MySQL configuration file
    mysql_config_file="/etc/mysql/my.cnf"

    # Turn off MySQL’s performance schema to reduce its memory usage
    echo "[mysqld]" | sudo tee "$mysql_config_file"
    echo "performance_schema=0" | sudo tee -a "$mysql_config_file"

    # Add MySQL root user and password to the configuration file to make it easy to access at the command line
    echo "[client]" | sudo tee -a "$mysql_config_file"
    echo "user=root" | sudo tee -a "$mysql_config_file"
    echo "password=$mysql_password" | sudo tee -a "$mysql_config_file"

    #Restart MySQL and log in:
    # DEBUG ECHO
    sudo /etc/init.d/mysql restart

    # Connect to MySQL using the configuration file
#    sudo mysql --defaults-extra-file="$mysql_config_file"

    # Optional: Remove MySQL user and password from the configuration file but it's worth noting it's stored in Ghost config.production.json
    # sed -i '/^\[client\]$/,/^\(user=root\|password=\)$/d' "$mysql_config_file"
}

# Function to validate a given URL
validate_url() {
  # If URL starts with 'http' or 'https', return 0 (success)
  case "$1" in
    http*://*) return 0;;
    # Otherwise, return 1 (failure)
    *) return 1;;
  esac
}

# Function to get a valid URL from the user
get_valid_url() {
  # Start an infinite loop until a valid URL is obtained
  while :; do
    # Prompt the user for a URL
    read -p "Enter the URL where you plan to host your Ghost blog (including http:// or https://): " url

    # Check if the URL field is empty
    if [ -z "$url" ]; then
      # Prompt the user to use the instance's IP address
      read -p "You didn't enter a URL. Do you want to use the instance's IP address ($INSTANCE_IP)? [y/n]: " use_ip

      # If user confirms, set the URL to the instance IP and break the loop
      if [ "$use_ip" = "y" ]; then
        url="http://$INSTANCE_IP"
        break
      fi
      # If the user doesn't confirm, loop back
      continue
    fi

    # Validate the entered URL
    if validate_url "$url"; then
      # Confirm the valid URL with the user
      read -p "You entered $url. Is this correct? [y/n]: " confirm

      # If the user confirms, break the loop
      if [ "$confirm" = "y" ]; then
        break
      fi
    else
      # If the URL is invalid, show an error message and loop back
      echo "Invalid URL format. Make sure it starts with http:// or https:// and is a valid domain."
      continue
    fi
  done
}


set_up_ghost() {
    # Install Ghost CLI
    # sudo npm install ghost-cli@latest -g
    echo "Installing Ghost CLI" >> debug.log
    sudo npm install ghost-cli@latest -g >> debug.log 2>&1


    #Make a new directory called ghost, set its permissions, then navigate to it:
    sudo mkdir -p /var/www/ghost
    sudo chown service-account:service-account /var/www/ghost
    sudo chmod 775 /var/www/ghost

    # Prompt for the Ghost URL using the validate_url and get_valid_url functions
    # read -p "Enter the URL where you plan to host your Ghost blog including http:// or https://: " url
    echo "Getting valid Ghost URL..." >> debug.log
    # functions to get a user entered URL are not working so disabling and hardcoding for now (also chaning url in config from $url to http://localhost:2368/)
    # get_valid_url

    # Define the path to save the config.production.json file
    config_file_path="/var/www/ghost/config.production.json"

    # Create a config.production.json file with the Ghost URL and MySQL password set by variables
    echo "Creating config.production.json file..." >> debug.log
    cat <<EOF > "$config_file_path"
    {
        "url": "http://localhost:2368/",
        "database": {
            "client": "mysql",
            "connection": {
                "host": "localhost",
                "user": "root",
                "password": "$mysql_password",
                "database": "ghost_prod"
            }
        },
        "server": {
            "host": "127.0.0.1",
            "port": 2368
        }
    }
EOF

    echo "Config file saved to $config_file_path" >> debug.log

    # Navigate to the website folder and install Ghost:
    cd /var/www/ghost && ghost install --no-prompt --setup-mysql --setup-nginx --setup-ssl --setup-systemd --start

    # For reasons I do not understand MySQL might error so this will try to address the issue
    # Create a new temporary SQL file
    sql_file2=$(mktemp)

    if [ -z "$sql_file2" ]; then
    echo "Failed to create a second temporary SQL file."
    exit 1
    fi

    # Add MySQL commands to address the issue
    echo "Line 220 Addressing MySQL issues, if any..."
    cat <<EOF > "$sql_file2"
    ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$mysql_password';
EOF

    # Execute MySQL commands
    sudo mysql -u root < "$sql_file2"

    # Clean up the temporary SQL file
    rm -f "$sql_file2"

    #then run:
    echo "Line 233 Starting Ghost..."
    ghost start 
}

enable_ghost_auto_start() {
    #Enable Autostart from the home directory of service_account, run:
    cd

    # Define the command to add to the cron job in this case starting ghost on reboot
    CRON_COMMAND="@reboot cd /var/www/ghost && /usr/bin/ghost start"

    # Use echo and a pipe to add the command to the crontab
    echo "$CRON_COMMAND" | crontab -

    # Verify that the command has been added
    crontab -l
}

main() {
    install_ghost_dependencies
    set_up_ghost
    enable_ghost_auto_start
}

main
