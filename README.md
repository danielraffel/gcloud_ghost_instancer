# [Blog Post](https://danielraffel.me/2023/09/18/learning-about-google-cloud-by-developing-a-ghost-org-installer/) covering additional details about this project

**About**

This script aims to facilliate setting up a self-hosted [Ghost.org](Ghost.org) instance on Google Cloud without a lot of hassle. I recently embarked on learning more about Google's Cloud and decided to automate this process, using the Google Cloud Command Line Interface (CLI) and various Google services. Google Cloud has a free-tier E2-Micro instance server ideal for running low traffic websites or blogs. I figured why not make it accessible to more people?

While attempting to run this installer on an E2-Micro (1GB) instance, I encountered frequent timeouts and maxed-out memory. Even upgrading to an E2-Small (2GB) didn't solve the issue. Ultimately, I opted for an E2-Medium (4GB) instance to ensure stability for setup. And, downgraded to an E2-Micro post setup. This incurs a nominal one-time cost

At time of writing an E2-Micro instance has up to 1GB RAM, 30GB storage, 1TB monthly transfer, can run 24/7 and falls under [Google Cloud's Always Free Tier]([url](https://cloud.google.com/free/docs/free-cloud-features)), which means you won't incur any costs running it, subject to Google's terms and usage limits. 

**Requirements**

* Google account
* [gcloud CLI](https://cloud.google.com/sdk/docs/install) installed (if not pre-installed the script will assist installing it for you)
* macOS
* Previously set up [Mailgun.com](Mailgun.com) account if you want to configure sending emails (you'll need to provide your username/password)

**Usage**

```
git clone git@github.com:danielraffel/gcloud_ghost_instancer.git
cd repo-directory
sh gcloud_ghost_instancer.sh
```

**Instructions**

Follow on-screen prompts for customization. These include free VM creation, automatically downloading the gcloud CLI, and more. I walk through them below in Post Setup Screen Action Items.

**Troubleshooting**

[File issues](https://github.com/danielraffel/gcloud_ghost_instancer/issues/new) to report problems.

**Security & Secrets**

* Generates local SSH keys stored at `$HOME/.ssh/` for
   * **root** `root_key-YOUR.INSTANCE.NAME-ghost`
   * **service-account** `service_account_key-YOUR.INSTANCE.NAME-ghost`
* Passwords and setup params stored in [Google Secret Manager](https://cloud.google.com/secret-manager/). They are labeled as follows:
   * **mysql root password** `mysql-password-YOUR.INSTANCE.NAME-ghost`
   * **service-account** `service-account-password-YOUR.INSTANCE.NAME-ghost`
   * **root** `root-password-YOUR.INSTANCE.NAME-ghost`
* The script `gcloud_ghost_instancer.sh` asks how you want to customize your Ghost install. The parameters you define during setup are stored in `ghost_install_setup_parameters-YOUR.INSTANCE.NAME-ghost` in [Google Secret Manager](https://cloud.google.com/secret-manager/) and appended to the Ghost installer on your VM at runtime as follows. This is a complate list of the parameters that are passed:
```
ghost install $ghost_install_setup_parameters --setup-mysql --setup-nginx --setup-ssl --setup-systemd --db mysql --dbhost localhost --dbuser root --dbpass $mysql_password --dbname ghost_prod --process systemd --enable --no-stack --port 2368 --ip 127.0.0.1
```
* The content of `ghost_install_setup_parameters` will:
   * **Always** include the URL where you will host Ghost
`--url $url`
   * **Optionally** include Mailgun settings if you opt to share your `mailgun_username` and `mailgun_username` with the installer:
```
--mail SMTP --mailservice Mailgun --mailuser $mailgun_username --mailpass $mailgun_username --mailhost $smtp_mailgun --mailport 2525
```
* Post-setup to SSH into your machine to do things like edit your config.production.json file and more go to your terminal and run:
```
ssh -i $HOME/.ssh/service_account_key-INSTANCE_NAME -o IdentitiesOnly=yes service-account@INSTANCE_IP
```
* Note: You will need to update your instance Name and External IP
   * You can obtain these details under "Name" and "External IP" in the [GCP Console](https://console.cloud.google.com/compute/instances)
* Or, you can run a gcloud command to fetch them in the terminal
```
gcloud compute instances list --format="table(name, networkInterfaces[0].accessConfigs[0].natIP)"
```

**Cleanup**

It's entirely possible the script may fail, leaving you with a running VM. While I do not expect that to occur I advise you to check [GCP Console](https://console.cloud.google.com/compute/instances) to ensure you end up with an E2-Micro. You can also run this gCloud command after the script runs to see what's running.

```
gcloud compute instances list
```

A temp file is generated on your local machine to store variables the script needs access to after exiting the SSH session. You can search the code to see what is stored. On your local machine the script `gcloud_ghost_instancer.sh` creates and removes this file:
```
$HOME/temp_vars.sh
```
Temp files are created on your VM to generate some SQL commands that run to optimize your DB without opening the mysql prompt. The script `install_on_server.sh` creates and removes these files:
```
sql_file
sql_file2
```

**Known Issues**

* Installer is not optimized to be installed on a free-tier E2-Micro
* Ghost installation presents a few errors but is still functional. This is likely due to the installer running in a pseudo terminal and as far as I know are not actual issues.
* Not tested on Linux / Windows. To run this on platforms you will need the [Google Cloud CLI](https://cloud.google.com/sdk/docs/install). The script checks and installs this for macOS but doesn't do that for other platforms.
* SSL was setup with a no-prompt installer. And, this may only supports https. I don't know that for certain so for now the script doesn't currently block setting up http Blog URLs.
   * I'm accustomed to a few extra steps setting up Lets Encrypt. One day I might run this with a new domain and write the final setup steps for hosting DNS via SSL. If you beat me to that please share!
* I have not personally tested end-to-end Mailgun setup with these flows (but it likely works since it leans on the script just collecting parameters and passing them to Ghost installer to generate the config correctly.) 

**Additional Information**

* This script is provided for informational purposes only. It is not officially supported by me or Google Cloud.
* The script likely contain bugs. Please use it at your own risk.
* Learn about [Google Secret Manager](https://cloud.google.com/secret-manager/)
* There are some Post Setup Action Items that will be required such as configuring your Ghost install with your DNS.

**Post Setup Action Items**

DNS configuration! You'll need to configure your Ghost instance to work with your DNS. This is currently outside of the scope of this installer and read me.

* For now, I'd advise following [Scott's setup guide](https://scottleechua.com/blog/self-hosting-ghost-on-google-cloud/):
   * [Step 2: Configuring your Domain](https://scottleechua.com/blog/self-hosting-ghost-on-google-cloud/#2-configure-the-domain)
   * [Step 5: Finish Cloudflare configuration on this excellent setup site](https://scottleechua.com/blog/self-hosting-ghost-on-google-cloud/#5-finish-cloudflare-configuration)

**Potential Future Enhancements**

* Automate DNS and SSL setup.
* Explore ways to customize additional install options.

**Setup Screen Action Items**
Below are the steps you'll be walked through in the script.

**Step 1)** This script will help you set up and run a Google Compute Engine E2-Micro virtual machine with Ghost.org installed.

An E2-Micro instance has up to 1GB RAM, 30GB storage, 1TB monthly transfer, can run 24/7 and falls under Google Cloud's Always Free Tier, which means you won't incur any costs, subject to Google's terms and usage limits.
Learn more: https://cloud.google.com/free/docs/free-cloud-features#free-tier-usage-limits

_Do you want to proceed? (y/n): y_

**Step 2)** To create a free E2-Micro instance, you'll need to setup your VM in a colocation facility that supports free-tiers. Pick the one closest to you.

 1) Oregon: us-west1
 2) Iowa: us-central1
 3) South Carolina: us-east1

_Select a zone that sounds like it's located closest to you: 1_

**Step 3)** Enter your blog URL (include http:// or https://):  https://ketchup.com
* _You entered: https://ketchup.com. Is this URL correct? (y/n): y_
* Will setup Ghost with https://ketchup.com. Continuing...

**Step 4)** Do you want to setup Ghost to send emails using Mailgun? (y/n):
* Note: if you select yes you'll need to have your mailgun username and password handy

**Step 5)** This script will create a VM named 'ghost' you have the option to add a custom prefix (eg daniel-ghost)
* _Do you want to add a customize prefix to your VM? (y/n): y_
* _Customize the prefix for your VM (e.g. 'yourprefix-ghost'):: ketchup_
* Your VM will be named: ketchup-ghost

**Step 6)** Creates SSH keys for service-account VM user on your local machine @ `$HOME/.ssh/service_account_key-ketchup-ghost`
* _Note: you'll be asked to simply press return (no need to enter a password)_
   * Enter passphrase (empty for no passphrase):
   * Enter same passphrase again:

**Step 7)** Creates SSH keys for root VM user on your local machine @ `$HOME/.ssh/root_key-ketchup-ghost`
* _Note: similar to step 6 you'll be asked to simply press return (no need to enter a password)_
   * Enter passphrase (empty for no passphrase):
   * Enter same passphrase again:

**Last Bits** Assuming all runs smoothly the rest of the installer is automated. It should end with these things being installed

```
Blog URL: https://ketchup.com
MySQL hostname: localhost
MySQL username: root
MySQL password: <mysql-password-YOUR.INSTANCE.NAME-ghost -- accessible in Google Secret Manager>
Ghost database name: ghost_prod
Set up Ghost MySQL user? — Y
Set up NGINX? — Y
Set up SSL? — Y
Set up systemd? — Y
Start Ghost? — Y
```

**At the very end** 
* You'll be briefly SSH'd into your E2-Micro instance where you'll see the status of your server.
* The script completes and the SSH session exits.
