#!/usr/bin/env python3
"""
SMTP Server Validator
Validates SMTP server connectivity, authentication, and email sending capability.
"""

import smtplib
import ssl
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime


def validate_smtp_server(
    smtp_server,
    smtp_port,
    username,
    password,
    from_email,
    to_email,
    use_tls=True,
    use_ssl=False
):
    """
    Validate SMTP server and attempt to send a test email.

    Args:
        smtp_server: SMTP server hostname (e.g., 'smtp.gmail.com')
        smtp_port: SMTP port (typically 587 for TLS, 465 for SSL, 25 for no encryption)
        username: Authentication username
        password: Authentication password
        from_email: Sender email address
        to_email: Recipient email address for test
        use_tls: Use STARTTLS encryption (default: True)
        use_ssl: Use SSL/TLS from connection start (default: False)

    Returns:
        dict: Results of validation with status and messages
    """
    results = {
        'connection': False,
        'authentication': False,
        'email_sent': False,
        'messages': []
    }

    server = None

    try:
        # Create SSL context for secure connection
        context = ssl.create_default_context()

        # Step 1: Connect to SMTP server
        print(f"Connecting to {smtp_server}:{smtp_port}...")

        if use_ssl:
            # Use SMTP_SSL for port 465
            server = smtplib.SMTP_SSL(smtp_server, smtp_port, context=context)
            results['messages'].append(f"Connected via SSL to {smtp_server}:{smtp_port}")
        else:
            # Use regular SMTP for port 587 or 25
            server = smtplib.SMTP(smtp_server, smtp_port)
            results['messages'].append(f"Connected to {smtp_server}:{smtp_port}")

            if use_tls:
                # Upgrade connection to TLS
                server.starttls(context=context)
                results['messages'].append("TLS encryption enabled")

        results['connection'] = True

        # Optional: Get server capabilities
        server.ehlo()

        # Step 2: Authenticate
        print(f"Authenticating as {username}...")
        server.login(username, password)
        results['authentication'] = True
        results['messages'].append(f"Authentication successful for {username}")

        # Step 3: Compose and send test email
        print(f"Sending test email to {to_email}...")

        message = MIMEMultipart("alternative")
        message["Subject"] = "SMTP Server Validation Test"
        message["From"] = from_email
        message["To"] = to_email
        message["Date"] = datetime.now().strftime("%a, %d %b %Y %H:%M:%S %z")

        # Create plain text and HTML versions
        text_content = f"""
SMTP Server Validation Test

This is a test email sent at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

SMTP Server: {smtp_server}:{smtp_port}
Authentication: Successful
        """

        html_content = f"""
        <html>
            <body>
                <h2>SMTP Server Validation Test</h2>
                <p>This is a test email sent at <strong>{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</strong></p>
                <ul>
                    <li><strong>SMTP Server:</strong> {smtp_server}:{smtp_port}</li>
                    <li><strong>Authentication:</strong> Successful</li>
                </ul>
            </body>
        </html>
        """

        # Attach both versions
        part1 = MIMEText(text_content, "plain")
        part2 = MIMEText(html_content, "html")
        message.attach(part1)
        message.attach(part2)

        # Send email
        server.sendmail(from_email, to_email, message.as_string())
        results['email_sent'] = True
        results['messages'].append(f"Test email sent successfully to {to_email}")

        print("✓ All validations passed!")

    except smtplib.SMTPAuthenticationError as e:
        results['messages'].append(f"Authentication failed: {str(e)}")
        print(f"✗ Authentication failed: {e}")

    except smtplib.SMTPConnectError as e:
        results['messages'].append(f"Connection failed: {str(e)}")
        print(f"✗ Connection failed: {e}")

    except smtplib.SMTPException as e:
        results['messages'].append(f"SMTP error: {str(e)}")
        print(f"✗ SMTP error: {e}")

    except Exception as e:
        results['messages'].append(f"Unexpected error: {str(e)}")
        print(f"✗ Unexpected error: {e}")

    finally:
        # Close connection
        if server:
            try:
                server.quit()
                results['messages'].append("Connection closed")
            except:
                pass

    return results


def print_results(results):
    """Print validation results in a formatted way."""
    print("\n" + "="*60)
    print("SMTP VALIDATION RESULTS")
    print("="*60)
    print(f"Connection:     {'✓ Success' if results['connection'] else '✗ Failed'}")
    print(f"Authentication: {'✓ Success' if results['authentication'] else '✗ Failed'}")
    print(f"Email Sent:     {'✓ Success' if results['email_sent'] else '✗ Failed'}")
    print("\nDetails:")
    for msg in results['messages']:
        print(f"  - {msg}")
    print("="*60)


if __name__ == "__main__":
    # Configuration - UPDATE THESE VALUES
    SMTP_CONFIG = {
        'smtp_server': 'smtp.gmail.com',      # e.g., smtp.gmail.com, smtp-mail.outlook.com
        'smtp_port': 587,                      # 587 for TLS, 465 for SSL
        'username': 'your.email@gmail.com',    # Your email/username
        'password': 'your_app_password',       # Your password or app-specific password
        'from_email': 'your.email@gmail.com',  # Sender address
        'to_email': 'recipient@example.com',   # Test recipient
        'use_tls': True,                       # Use STARTTLS
        'use_ssl': False                       # Use SSL from start (for port 465)
    }

    # Run validation
    results = validate_smtp_server(**SMTP_CONFIG)

    # Print results
    print_results(results)

    # Exit with appropriate status code
    exit(0 if results['email_sent'] else 1)
