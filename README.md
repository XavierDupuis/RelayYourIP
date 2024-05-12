# RelayYourIP

RelayYourIP is a lightweight tool designed to monitor and relay changes in your public IP address. It provides instant notifications, making it ideal for maintaining seamless remote access and enhancing network security.

## Features

- Periodically checks for changes in the public IP address.
- Sends instant notifications upon detection of modifications.
- Supports custom actions to be executed when the IP address changes.
- Simple and easy-to-use for enhanced network efficiency.


## Configuration

### Environment Variables

- `LABEL`: Label to identify your server in notifications.
- `MSMTP_ACCOUNT`: Your msmtp account identifier.
- `MSMTP_HOST`: SMTP server hostname.
- `MSMTP_PORT`: SMTP server port.
- `MSMTP_FROM`: Sender email address.
- `MSMTP_USER`: SMTP server username.
- `MSMTP_PASSWORD`: SMTP server password.
- `RECIPIENTS_EMAILS`: Recipient email addresses (comma-separated if multiple).
- `CRON_SCHEDULE`: Cron job frequency for IP checks. See [crontab.guru](https://crontab.guru/)

### Configuration File

The `config.yml` file defines custom behavior executed when the IP address changes. Here's an example configuration :

```yaml
# config.yml
actions:
  - description: "Update Dynamic DNS at afraid.org"
    command: "curl -s http://sync.afraid.org/u/<token>"
  - description: "Update Dynamic DNS at duckdns.org"
    command: "curl -s https://www.duckdns.org/update?domains=<domain>&token=<token>&ip=$UPDATED_IP"
  - description: "Post Discord Webhook Notification"
    command: "curl -X POST -H \"Content-Type: application/json\" -d '{ \"embeds\": [{ \"title\": \"RelayYourIP\", \"color\": 7151075, \"fields\": [{ \"name\": \"Updated server IP\", \"value\": \"$UPDATED_IP\" }] }] }' https://discord.com/api/webhooks/<channel>/<token>"
```


**Notes**

- Make sure to replace `<token>` and `<domain>` (or any other field) with your actual dynamic DNS information, if necessary.
- The script supports dynamic substitution of the $UPDATED_IP placeholder in the commands with the actual IP address.

## Usage

### Using Docker Compose

To integrate RelayYourIP using Docker Compose, follow these steps:

1. **Create a Docker Compose file (`docker-compose.yml`):**

    - With environement variables directly : 

      ```yaml
      # docker-compose.yml
      services:
        relayyourip:
          image: ghcr.io/xavierdupuis/relayyourip:main
          environment:
            - LABEL=YourServerName
            - MSMTP_ACCOUNT=your_account
            - MSMTP_HOST=smtp.example.com
            - MSMTP_PORT=587
            - MSMTP_FROM=your_email@example.com
            - MSMTP_USER=your_username
            - MSMTP_PASSWORD=your_password
            - RECIPIENTS_EMAILS=recipient@example.com
            - CRON_SCHEDULE=*/30 * * * *
          volumes:
            - /etc/localtime:/etc/localtime:ro
            - ./confg.yml/:/app/config.yml
          restart: always
      ```

    - With `.env` file (using the `.env.template` file): 

      ```yaml
      # docker-compose.yml
      services:
        relayyourip:
          image: ghcr.io/xavierdupuis/relayyourip:main
          env_file:
            - .env
          volumes:
            - /etc/localtime:/etc/localtime:ro
            - ./confg.yml/:/app/config.yml
          restart: always
      ```

      ```bash
      # .env
      LABEL=YourServerName
      MSMTP_ACCOUNT=your_account
      MSMTP_HOST=smtp.example.com
      MSMTP_PORT=587
      MSMTP_FROM=your_email@example.com
      MSMTP_USER=your_username
      MSMTP_PASSWORD=your_password
      RECIPIENTS_EMAILS=recipient@example.com
      CRON_SCHEDULE=*/30 * * * *
      ```

    Adjust the environment variables as needed for your setup.

2. **Run the Docker Compose command:**

    ```bash
    docker compose up -d
    ```

    This will start RelayYourIP as a background service.

3. **Expected behavior**

    - Email format:

      ```bash
      From: your_email@example.com
      Subject: [YourServerName] IP Address Change Notification

      January 1, 1970 12:30 PM (UTC)

      123.45.67.89
      ```

## Development

### Using the Development Environment

Developers can use the `dev.docker-compose.yml` file to set up the development environment. This file includes configurations tailored for development purposes.

```bash
docker-compose -f dev.docker-compose.yml up --build
```

The `--build` flag ensures that the Docker image is rebuilt, incorporating any changes made to the source code.

**Note**: Ensure creating a `.env` file with the required environment variables before running the command above.

### Troubleshooting

If you encounter issues or want to explore further configurations, refer to the [Docker Compose documentation](https://docs.docker.com/compose/).

---

Feel free to customize this section further based on your specific development practices and requirements.


## License

This project is licensed under the [MIT License](LICENSE).
