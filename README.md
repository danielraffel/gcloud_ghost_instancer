Note: As of 9/16/23 this doesn't quite work yet...will return to it soon.

**README.md for gcloud_ghost_instancer.sh**

**About**

This script will help you set up and run a Google Compute Engine E2-Micro virtual machine with Ghost.org installed. An E2-Micro instance has up to 1GB RAM, 30GB storage, 1TB monthly transfer, can run 24/7 and falls under Google Cloud's Always Free Tier, which means you won't incur any costs, subject to Google's terms and usage limits.

**Requirements**

* Google account
* gcloud CLI installed (if not pre-installed the script will assist installing it for you)

**Usage**

To run the script, open a terminal and navigate to the directory containing the script. Then, run the following command:

```
sh gcloud_ghost_instancer.sh
```

**Instructions**

The script will prompt you for the following information, such as:

* Do you want to proceed with creating a free Virtual Machine on Google Cloud?
* Do you want to automatically download and install the gcloud CLI? (optional)
* Select a zone to create your free tier VM in.

Once you have provided all of the necessary information, the script will create the VM and install Ghost.org. You will then be provided with the IP address of your VM and instructions on how to access the Ghost admin panel.

**Troubleshooting**

If you encounter any problems, file issues.

**Known Issues**

As of 9/16/23 there remain installer bugs (eg memory constraints) preventing this from working. Considering future options. A simple work around might be to install this on a 2gb machine, image it and then run on a micro-instance. Would cost pennies if handled quickly and might be the easiest solution. Micro instances are resource constrained and struggle during installs and updates (often requiring creative workarounds to reduce memory footprint.)

**Additional Information**

* This script is provided for informational purposes only. It is not officially supported by Google Cloud.
* The script is still under development and may contain bugs. Please use it at your own risk.
* If you have any feedback or suggestions, please feel free to create an issue on GitHub.

**Things to note**

* The script creates ssh keys so you can access the server without a password, sets a root password, creates a service-account user and password and creates a mysql password. All passwords are stored in Google Secret Manager.
* You can find more information about Google Secret Manager here: [https://cloud.google.com/secret-manager/].
* You can access your VM in the Google Cloud Console here: [https://console.cloud.google.com/compute/instances].

**Potential Future Enhancements**

* Adding details when the script ends with personalized details about what was installed.
* Exploring more ways to customize the google cloud install options.
