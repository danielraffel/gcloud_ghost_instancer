#!/bin/bash

install_ghost_dependencies() {
    # Update Linux
    apt update && apt -y upgrade
    #free up RAM by disabling snap
    sudo systemctl stop snapd.service
    sudo systemctl disable snapd.service

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

    # Create a temporary MySQL Commands File
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
    # Reloads the privilege tables, ensuring that the changes made to user accounts and databases take effect immediately
#    sudo mysql -uroot -p$mysql_password -e "FLUSH PRIVILEGES"

    # #Restart MySQL and log in:
    # sudo /etc/init.d/mysql restart

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
    sudo /etc/init.d/mysql restart

    # Connect to MySQL using the configuration file
    # sudo mysql --defaults-extra-file="$mysql_config_file"

}

set_up_ghost() {
    # Install Ghost CLI
    sudo npm install ghost-cli@latest -g
    # sudo npm install ghost-cli@latest -g >> debug.log 2>&1

    #Make a new directory called ghost, set its permissions, then navigate to it:
    sudo mkdir -p /var/www/ghost
    sudo chown service-account:service-account /var/www/ghost
    sudo chmod 775 /var/www/ghost

    # Set up ghostuser, give them sudo and change folder ownership:
    adduser ghostuser
    usermod -aG sudo ghostuser
    sudo chown -R ghost:ghost /var/www/ghost/content

    # Navigate to the website folder and install Ghost:
    # cd /var/www/ghost && ghost install --no-prompt --setup-mysql --setup-nginx --setup-ssl --setup-systemd --start
    cd /var/www/ghost && ghost install --no-prompt --setup-mysql --setup-nginx --setup-ssl --setup-systemd --url https://$INSTANCE_IP --dbhost localhost --dbuser root --dbpass $mysql_password --dbname ghost_prod --start

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
EOF

    # Execute MySQL commands
    sudo mysql -u root < "$sql_file2"

    # Clean up the temporary SQL file
    rm -f "$sql_file2"

    #then run:
    ghost start 
}

enable_ghost_auto_start() {
    #Enable Autostart from the home directory of service_account, run:
    cd

    # Define the command to add to the cron job in this case starting ghost on reboot
    CRON_COMMAND="@reboot /bin/bash -c 'cd /var/www/ghost && ghost start'"

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
