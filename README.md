**README.md for gcloud_ghost_instancer.sh**

**About**

This script will help you set up and run a Google Compute Engine E2-Micro virtual machine with Ghost.org installed. An E2-Micro instance has up to 1GB RAM, 30GB storage, 1TB monthly transfer, can run 24/7 and falls under Google Cloud's Always Free Tier, which means you won't incur any costs running it, subject to Google's terms and usage limits. While it's possible to run Ghost on an E2-Micro automating the software install seems to tax the machine. Therefore, this script installs the software on an E2-Medium server, immediately stops it once complete and then re-starts the server as an E2-Micro. I presume this will incure some cost. If I had to guess I'm thinking it would be measured in cents?

**Requirements**

* Google account
* gcloud CLI installed (if not pre-installed the script will assist installing it for you)
* MacOS

**Usage**

Clone the repo, open a terminal and navigate to the directory containing the scripts. Then, run the following command:

```
sh gcloud_ghost_instancer.sh
```

**Instructions**

The script will prompt you for the following information, such as:

* Do you want to proceed with creating a free Virtual Machine on Google Cloud?
* Do you want to automatically download and install the gcloud CLI? (pre-requisite)
* etc...

Once you have provided all of the necessary information, the script will create the VM and install Ghost.org. You will then be provided with details of your VM and instructions on how to access the Ghost admin panel.

**Troubleshooting**

* If you encounter any problems, file issues. And, feel free to share any feedback or suggestions.

**Known Issues**

* The installer hasn't been optimized to be installed on a free-tier E2-Micro
* The installer has not been tested on Linux / Windows. At the very least it will definitely need support for checking/installing the Google Cloud CLI.
* After ghost installs it gives three bad looking errors. I dunno why because it works just fine. I suspect this is due to running in a pseudo terminal during setup. 
* The first error is: CliError. Message: Error trying to connect to the MySQL database. <-- it is setup fine
* The second error is: SystemError Message: Prompts have been disabled, all options must be provided via command line flags. <-- yep, we setup with prompts
* The third error is: GhostError Message: Ghost was able to start, but errored during boot with: Access denied for user 'root'@'localhost'
* I am unclear how SSL works when setup with no-prompt. It was installed by the installer but I'm accustomed to a few extra steps with Lets Encrypt.

**Additional Information**

* This script is provided for informational purposes only. It is not officially supported by me or Google Cloud.
* The script is likely contain bugs. Please use it at your own risk.
* The script creates SSH keys on your local machine (and uploads the public key to your VM) so that you can access the server without a password. The keys for the users created on your VM are located in $HOME/.ssh/ for root (root_key-YOUR.INSTANCE.NAME-ghost) and service-account (service_account_key-YOUR.INSTANCE.NAME-ghost)
* The VM sets a root password, creates a service-account user and password and creates a mysql password. 
* All passwords created by the script are stored in Google Secret Manager associated with your account. You can find your mysql root password (mysql-password-YOUR.INSTANCE.NAME-ghost), service-account (service-account-password-YOUR.INSTANCE.NAME-ghost) and root (root-password-YOUR.INSTANCE.NAME-ghost).
* The installer asks how you want to customize Ghost install. The parameters you define are also stored in Google Secret Manager since it's a handy synced datastore. You can find what your ghost was configured with at: ghost_install_setup_parameters-YOUR.INSTANCE.NAME-ghost.
* You can find more information about Google Secret Manager here: [https://cloud.google.com/secret-manager/].
* You can access your VM in the Google Cloud Console here: [https://console.cloud.google.com/compute/instances].
* The setup flow supports setting up Mailgun.com to send emails but you'll need to have already registered a username/password. I have not tested it (likely works.)
* If the script fails it is possible you'll end up with a partially running VM. Since it could theoretically fail when installing on a premium VM I would check the Google Cloud Console after each run and click on the instance to confirm you got an E2-Micro: [https://console.cloud.google.com/compute/instances]
* There are some post-run setup flows that will be required such as configuring your Ghost install with your DNS.

**Potential Future Enhancements**

* Adding details when the script ends with personalized details about what was installed.
* Exploring more ways to customize the google cloud install options.

**Setup Screen Action Items**

Step 1) This script will help you set up and run a Google Compute Engine E2-Micro virtual machine with Ghost.org installed.

An E2-Micro instance has up to 1GB RAM, 30GB storage, 1TB monthly transfer, can run 24/7 and falls under Google Cloud's Always Free Tier, which means you won't incur any costs, subject to Google's terms and usage limits.
Learn more: https://cloud.google.com/free/docs/free-cloud-features#free-tier-usage-limits

Do you want to proceed? (y/n): y

Step 2) To create a free E2-Micro instance, you'll need to setup your VM in a colocation facility that supports free-tiers.

 1) Oregon: us-west1
 2) Iowa: us-central1
 3) South Carolina: us-east1

Select a zone that sounds like it's located closest to you: 1

Step 3) Enter your blog URL (include http:// or https://):  https://ketchup.com
You entered: https://ketchup.com. Is this URL correct? (y/n): y
Will setup Ghost with https://ketchup.com. Continuing...

Step 4) Do you want to setup Ghost to send emails using Mailgun? (y/n):(if you select yes you'll need to have your mailgun username and password handy)

Step 5) This script will create a VM named 'ghost' you have the option to add a custom prefix (eg daniel-ghost)
Do you want to add a customize prefix to your VM? (y/n): y
Customize the prefix for your VM (e.g. 'yourprefix-ghost'):: ketchup
Your VM will be named: ketchup-ghost

Step 6) Creates SSH keys for service-account VM user on your local machine @ $HOME/.ssh/service_account_key-ketchup-ghost -- you'll be asked to simply press return
Enter passphrase (empty for no passphrase):
Enter same passphrase again:

Step 7) Creates SSH keys for root VM user on your local machine @ $HOME/.ssh/root_key-ketchup-ghost -- (you'll be asked to simply press return)
Enter passphrase (empty for no passphrase):
Enter same passphrase again:

Assuming all runs smoothly the rest of the installer is automated. It should end with

Blog URL: https://ketchup.com
MySQL hostname: localhost
MySQL username: root
MySQL password: <accessible in Google Secret>
Ghost database name: ghost_prod
Set up Ghost MySQL user? — Y
Set up NGINX? — Y
Set up SSL? — Y
Set up systemd? — Y
Start Ghost? — Y

At the very end you'll be briefly SSH'd into your Micro-Instance and should see this:

┌─────────────┬────────────────┬─────────┬──────────────────────┬─────────────────────┬──────┬─────────────────┐
│ Name        │ Location       │ Version │ Status               │ URL                 │ Port │ Process Manager │
├─────────────┼────────────────┼─────────┼──────────────────────┼─────────────────────┼──────┼─────────────────┤
│ ketchup-com │ /var/www/ghost │ 5.63.0  │ running (production) │ http://ketchup.com  │ 2368 │ systemd         │
└─────────────┴────────────────┴─────────┴──────────────────────┴─────────────────────┴──────┴─────────────────┘


To ssh into your machine to do things like edit your config.production.json file and more go to your terminal an run...
ssh -t -i $HOME/.ssh/service_account_key-ketchup-ghost -o IdentitiesOnly=yes service-account@YourInstanceIP

Note: You will need to update YourInstanceIP with your external IP for your instance from [https://console.cloud.google.com/compute/instances]

**Post Setup Action Items**

DNS configuration! You'll need to configure your Ghost instance to work with your DNS. This is currently outside of the scope of this installer and read me.

For now, I'd advise following Step 2 Configuring your Domain and Step 5 Finish Cloudflare configuration on this excellent setup site: https://scottleechua.com/blog/self-hosting-ghost-on-google-cloud/
