#!/bin/bash
    #Make a new directory called ghost, set its permissions, then navigate to it:
    sudo mkdir -p /var/www/ghost
    sudo chown service-account:service-account /var/www/ghost
    sudo chmod 775 /var/www/ghost

    # Navigate to the website folder and install Ghost:
    cd /var/www/ghost && ghost install
