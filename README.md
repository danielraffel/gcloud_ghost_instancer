**About**

Automate the setup of a Google Compute Engine E2-Micro VM running [Ghost.org](Ghost.org) on macOS. Setup starts on a premium E2-Medium VM due to server load. And, ends with an Always Free tier VM running on an E2-Micro. Minimal setup costs, likely cents.

Note: An E2-Micro instance has up to 1GB RAM, 30GB storage, 1TB monthly transfer, can run 24/7 and falls under Google Cloud's Always Free Tier, which means you won't incur any costs running it, subject to Google's terms and usage limits. 

**Requirements**

* Google account
* [gcloud CLI](https://cloud.google.com/sdk/docs/install) installed (if not pre-installed the script will assist installing it for you)
* MacOS

**Usage**

```
git clone repo-url
cd repo-directory
sh gcloud_ghost_instancer.sh
```

**Instructions**

Follow on-screen prompts for customization. These include free VM creation, automatically downloading the gcloud CLI, and more.

**Troubleshooting**

File issues for problems. Known issues:

**Security & Secrets**

* Generates SSH keys stored at $HOME/.ssh/
* Passwords and setup params stored in Google Secret Manager

**Cleanup**

It's possible the script may fail, leaving a partial VM. Check [GCP Console](https://console.cloud.google.com/compute/instances) to ensure you end up with an E2-Micro.

**Known Issues**

* Installer not optimized to be installed on a free-tier E2-Micro
* Errors during Ghost installation (still functional and likely due to running in a pseudo terminal eg not legit issues)
* Not tested on Linux/Windows
* Not tested on Linux / Windows. Will need support for checking/installing the Google Cloud CLI.
* SSL was setup but with a no-prompt installer. I'm accustomed to a few extra steps with Lets Encrypt, needs investigation.

**Additional Information**

* This script is provided for informational purposes only. It is not officially supported by me or Google Cloud.
* The script likely contain bugs. Please use it at your own risk.
* The script creates SSH keys on your local machine (and uploads the public key to your VM) so that you can access the server without a password. The keys for the users created on your VM are located in $HOME/.ssh/ for root (root_key-YOUR.INSTANCE.NAME-ghost) and service-account (service_account_key-YOUR.INSTANCE.NAME-ghost)
* The VM sets a root password, creates a service-account user and password and creates a mysql password. 
* All passwords created by the script are stored in Google Secret Manager associated with your account. You can find your mysql root password (mysql-password-YOUR.INSTANCE.NAME-ghost), service-account (service-account-password-YOUR.INSTANCE.NAME-ghost) and root (root-password-YOUR.INSTANCE.NAME-ghost).
* The installer asks how you want to customize Ghost install. The parameters you define are also stored in Google Secret Manager since it's a handy synced datastore. You can find what your ghost was configured with at: ghost_install_setup_parameters-YOUR.INSTANCE.NAME-ghost.
* Learn about [Google Secret Manager](https://cloud.google.com/secret-manager/)
* The setup flow supports setting up [Mailgun.com](Mailgun.com) to send emails but you'll need to have already registered a username/password. I have not tested it (but likely works.)
* There are some Post Setup Action Items that will be required such as configuring your Ghost install with your DNS.

**Post Setup Action Items**

DNS configuration! You'll need to configure your Ghost instance to work with your DNS. This is currently outside of the scope of this installer and read me.

For now, I'd advise following [Scott's setup guide](https://scottleechua.com/blog/self-hosting-ghost-on-google-cloud/):
- Step 2: Configuring your Domain
- Step 5: Finish Cloudflare configuration on this excellent setup site

**Potential Future Enhancements**

* Automate DNS and SSL setup.
* Explore ways to customize additional install options.

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

```
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
```

At the very end you'll be briefly SSH'd into your Micro-Instance and should see the status of your server.

In the future, to ssh into your machine to do things like edit your config.production.json file and more go to your terminal and run:
```
ssh -t -i $HOME/.ssh/service_account_key-ketchup-ghost -o IdentitiesOnly=yes service-account@YourInstanceIP
```
Note: You will need to update YourInstanceIP with your external IP for your instance from [GCP Console](https://console.cloud.google.com/compute/instances)
