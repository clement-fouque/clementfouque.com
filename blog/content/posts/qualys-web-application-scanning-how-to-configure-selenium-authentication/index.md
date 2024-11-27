+++
title = "Qualys Web Application Scanning: how to configure Selenium authentication?"
date = 2024-09-29
summary = "Why and how configuring authentication on Qualys Web Application Scanning with a selenium script"
slug = 'qualys-web-application-scanning-how-to-configure-selenium-authentication'
draft = false
+++


Securing web applications is an essential aspect of protecting an infrastructure from cyber threats. A key step in this process is conducting authenticated scans to identify vulnerabilities that could be exploited by malicious users. In this blog post, I'll walk through the process of configuring Selenium authentication with the [Qualys Web Application Scanner](https://www.qualys.com/apps/web-app-scanning/) (WAS).

## Why and how performing an authenticated scan?

Performing an authenticated scan is essential for testing web applications that have restricted areas or require user authentication to access. By using authenticated scanning, you can simulate different user roles within your application, gaining a more comprehensive understanding of its security posture.

Qualys Web Application Scanning (WAS) offers various authentication methods to help you achieve this:

- Form-based authentication: 
  - Standard Login: A straightforward login process that's easy to configure.
  - Custom: More flexibility in setting up your login process, but still limited in its customization capabilities.
  - Selenium script: The ultimate level of control, allowing you to script every step of the authentication process. This is particularly useful for complex or custom authentication flows.
- OAuth2 authentication:
    - Authorisation Code
    - Implicit
    - Client Credentials
    - Resource Owner Password Credentials
- Server-based authentication:
  - Basic
  - Digest
  - NTLM

Based on [Qualys documentation](https://qualysguard.qg2.apps.qualys.com/portal-help/en/was/authentication/authentication_basics.htm), OAuth2 should only be used for Swagger/Open API file authentication.

 I'll delve into configuring form-based authentication using Selenium. This approach provides full control over the authentication process, making it ideal when custom scripts are required. Selenium can also be used for OAuth2 authentication.

## What is Selenium?

Selenium is an open-source framework widely utilized for automating browser-based interactions and testing web applications. It offers robust features that allow developers and testers to interact with various elements on a webpage programmatically, making it an ideal choice for automating tasks such as user authentication. In our example, I’ll utilize Selenium's capabilities to authenticate on a login form page

## Creating the selenium authentication with Qualys Browser Recorder extension

The easiest way to create a selenium Qualys WAS authentication script is to [install the extension](https://chromewebstore.google.com/detail/qualys-browser-recorder/abnnemjpaacaimkkepphpkaiomnafldi) developed by Qualys. It seems only compatible with chrome based browsers.

Once installed, I clicked the *Record* button on the top right corner to start recording. Through the different actions I’ve done, I can see the commands that are listed within the Qualys extension. Once done I clicked on the stop record button. 

![Qualys Browser Recorder](qualys_browser_recorder.png)

I need to update commands to make them more generic and less tight to this current deployment. This is a manual work that can be done with the help  of the browser inspector. 

![Inspector Kibana authentication](inspector_kibana_authentication.png)

Here is the final selenium authentication script for authenticating on Kibana. 

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
    <head>
        <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
        <link rel="selenium.base" href="https://localhost:5601/" />
        <title>Kibana_Selenium_Auth</title>
    </head>
    <body>
        <table cellpadding="1" cellspacing="1" border="1">
            <thead>
                <tr><td rowspan="1" colspan="3">Kibana Login</td></tr>
            </thead>
            <tbody>
                <tr><td>open</td><td>https://localhost:5601/login</td><td></td></tr>
                <tr><td>waitForPageToLoad</td><td>30000</td><td></td></tr>
                <tr><td>waitForElementPresent</td><td>//input[@data-test-subj='loginUsername']</td><td></td></tr>
                <tr><td>type</td><td>//input[@data-test-subj='loginUsername']</td><td>elastic</td></tr>
                <tr><td>type</td><td>//input[@data-test-subj='loginPassword']</td><td>changeme</td></tr>
                <tr><td>click</td><td>//button[@data-test-subj='loginSubmit']</td><td></td></tr>
                <tr><td>open</td><td>https://localhost:5601/app/home#/</td><td></td></tr>
                <tr><td>waitForPageToLoad</td><td>30000</td><td></td></tr>
                <tr><td>waitForElementPresent</td><td>//button[@data-test-subj='userMenuButton']</td><td></td></tr>
            </tbody>
        </table>
    </body>
</html>
```

To verify that the Qualys Web Application Scanning integration with Selenium is working as expected, we can run the selenium script directly from within the Qualys Browser Recorder. Prior to running a test, it's crucial to clear any authentication cookies in the browser to guarantee successful authentication.

![Qualys Browser Recorder successfull test](qualys_browser_recorder_test_successfull.png)

The Selenium script used in our test case can be easily exported and the imported in Qualys. To do this, simply save the test case as follow.

![Qualys Browser Recorder save test case](qualys_browser_recorder_save_test_case.png)

## Creating the Qualys authentication record

In Qualys WAS, configuring Selenium-based scanning requires creating an authentication record that can be associated with one or multiple web applications.

To add a new authenticated record, we must go to _Configuration_ and then _Authentication_. The wizard is pretty straighforward. In the _regular expression to verify that the authentication completed successfully_, I've configured with `.*`, Qualys suggests to use _logout_, to ensure it's only accessible while logged in.

To add a new authenticated record, we must navigate to _Configuration_ and then _Authentication_. The wizard is straightforward to follow. When setting up the regular expression to verify successful authentication, I've configured with `.*`, Qualys suggests to use _logout_, to ensure it's only accessible while logged in.

![Qualys WAS new selenium authentication](qualys_was_selenium_authentication.png)

After creating the authentication record, the next step is to link it to the relevant web application(s) in Qualys. This can be done by accessing the drop-down menu on the recently created authentication record and clicking on _Add To Web Applications_. If we need to associate multiple authentication records with a single web application, we must simply repeat this process.

## Testing authentication

To validate the authentication mechanism of a web application, we must open the drop-down menu of the web applications and select _Test authentication_. We need to select the authentication record that will be evaluated. From my experience, this can can take around 30 minutes to complete.

Once complete, we can see the result in the _Scan List_ within _Scans_ tab. Reviewing the following QIDs in the scan report can be particularly helpful for troubleshooting purposes.

| QID | Name |
|---|---|
| 150094 | Selenium Web Application Authentication Was Successful |
| 150095 | Selenium Web Application Authentication Failed |
| 150100 | Selenium Diagnostics |

{{< alert "lightbulb">}}
Qualys is currently developing an updated scanning engine, which may address authentication issues experienced by some users. While I'm not aware of its specific features or release date, you can open a support case to have it enabled for your application(s) if desired. In my own experience, switching to this new engine resolved authentication problems that had previously been puzzling.
{{< /alert >}}

## Replacing variables with Qualys

Qualys provides a more secure way to store credentials directly in the configuration, rather than hardcoding them in the Selenium script. This approach reduces the risk of exposing sensitive information and makes it easier to update credentials if they change.

We have 3 variables available that we can use in our selenium script. I wasn't able to make the `@@webappURL@@` works, Qualys documentation contains [an example](https://docs.qualys.com/en/was/latest/web_applications/create_selenium_script.htm) though. 

To take advantage of this feature, we can use some of the three built-in variables in the Selenium script. While I was unable to get the `@@webappURL@@` variable working initially, Qualys documentation offers a helpful  [example](https://docs.qualys.com/en/was/latest/web_applications/create_selenium_script.htm) for implementation.

| WAS Parameter | Description |
|---|---|
|@@webappURL@@ | Use to fetch base URL of the web application. |
|@@authusername@@	| Use to fetch username of the login form. |
|@@authpassword@@	| Use to fetch password of the login form. |

## Conclusion

By automating the login process through Selenium authentication, testers can unlock deeper insights into potential security vulnerabilities hidden within restricted areas of their web applications. This streamlined approach not only saves time but also enables more comprehensive testing, revealing weaknesses that might otherwise go undetected.