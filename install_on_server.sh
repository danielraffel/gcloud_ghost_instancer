#!/bin/bash

install_ghost_dependencies () {
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

    # Get the IP for the instance
    INSTANCE_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

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
    QUIT;
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
    sudo mysql -uroot -p$mysql_password -e "UNINSTALL PLUGIN validate_password;"
    # Remove the anonymous user accounts, which can be a security risk if left in the MySQL database
    sudo mysql -uroot -p$mysql_password -e "DROP USER ''@'localhost'"
    # Allow Root Login Remotely -- don't think we need to do this
    # mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH 'mysql_native_password' BY 'your_password';"
    # Because our hostname varies we'll use some Bash magic here.
    sudo mysql -uroot -p$mysql_password -e "DROP USER ''@'$(hostname)'"
    # Drops the 'test' database, which is a default database that may not be needed in a production environment
    sudo mysql -uroot -p$mysql_password -e "DROP DATABASE test"
    # Reloads the privilege tables, ensuring that the changes made to user accounts and databases take effect immediately
    sudo mysql -uroot -p$mysql_password -e "FLUSH PRIVILEGES"

    # Define the MySQL configuration file
    mysql_config_file="/etc/mysql/my.cnf"

    # Turn off MySQL’s performance schema to reduce its memory usage
    # Using echo and tee to add configuration to my.cnf
    # echo "[mysqld]" > "$mysql_config_file"
    # echo "performance_schema=0" >> "$mysql_config_file"
    echo "[mysqld]" | sudo tee "$mysql_config_file"
    echo "performance_schema=0" | sudo tee -a "$mysql_config_file"

    #Restart MySQL and log in:
    sudo /etc/init.d/mysql restart

    # Add MySQL root user and password to the configuration file to make it easy to access at the command line
    # echo "[client]" > "$mysql_config_file"
    # echo "user=root" >> "$mysql_config_file"
    # echo "password=$mysql_password" >> "$mysql_config_file"
    echo "[client]" | sudo tee "$mysql_config_file"
    echo "user=root" | sudo tee -a "$mysql_config_file"
    echo "password=$mysql_password" | sudo tee -a "$mysql_config_file"


    # Connect to MySQL using the configuration file
    sudo mysql --defaults-extra-file="$mysql_config_file"

    # Optional: Remove MySQL user and password from the configuration file but it's worth noting it's stored in Ghost config.production.json
    # sed -i '/^\[client\]$/,/^\(user=root\|password=\)$/d' "$mysql_config_file"
}

# Function to validate a URL
validate_url() {
  if [[ $1 =~ ^https?://[a-zA-Z0-9.-]+$ ]]; then
    return 0
  else
    return 1
  fi
}

# Function to get a valid URL or use the instance IP
get_valid_url() {
  while :; do
    read -p "Enter the URL where you plan to host your Ghost blog (including http:// or https://): " url

    if [ -z "$url" ]; then
      read -p "You didn't enter a URL. Do you want to use the instance's IP address ($INSTANCE_IP)? [y/n]: " use_ip
      if [ "$use_ip" == "y" ]; then
        url="http://$INSTANCE_IP"
        break
      else
        echo "Please enter a valid URL."
      fi
    elif validate_url "$url"; then
      read -p "You entered $url. Is this correct? [y/n]: " confirm
      if [ "$confirm" == "y" ]; then
        break
      fi
    else
      echo "Invalid URL format. Make sure it starts with http:// or https:// and is a valid domain."
    fi
  done
}

set_up_ghost () {
    # Install Ghost CLI
    sudo npm install ghost-cli@latest -g

    #Make a new directory called ghost, set its permissions, then navigate to it:
    sudo mkdir /var/www/ghost
    sudo chown service_account:service_account /var/www/ghost
    sudo chmod 775 /var/www/ghost

    # Prompt for the Ghost URL using the validate_url and get_valid_url functions
    # read -p "Enter the URL where you plan to host your Ghost blog including http:// or https://: " url
    get_valid_url

    # Define the path to save the config.production.json file
    config_file_path="/var/www/ghost/config.production.json"

    # Create a config.production.json file with the Ghost URL and MySQL password set by variables
    cat <<EOF > "$config_file_path"
    {
        "url": "$url",
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

    echo "Config file saved to $config_file_path"

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
    cat <<EOF > "$sql_file2"
    ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$mysql_password';
    QUIT;
EOF

    # Execute MySQL commands
    sudo mysql -u root < "$sql_file2"

    # Clean up the temporary SQL file
    rm -f "$sql_file2"

    #then run:
    ghost start 
}

enable_ghost_auto_start () {
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
