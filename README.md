# RelayYourIP

RelayYourIP is a lightweight tool designed to monitor and relay changes in your public IP address. It provides instant notifications, making it ideal for maintaining seamless remote access and enhancing network security.

## Features

- Periodically checks for changes in the public IP address.
- Sends instant notifications upon detection of modifications.
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

## Usage

### Using Docker Compose

To integrate RelayYourIP using Docker Compose, follow these steps:

1. **Create a Docker Compose file (`docker-compose.yml`):**

    - With environement variables directly : 

      ```yaml
      # docker-compose.yml
      version: '3'
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
          restart: always
      ```

    - With `.env` file (using the `.env.template` file): 

      ```yaml
      # docker-compose.yml
      version: '3'
      services:
        relayyourip:
          image: ghcr.io/xavierdupuis/relayyourip:main
          env_file:
            - .env
          volumes:
            - /etc/localtime:/etc/localtime:ro
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

3. **Expected Email Notification format**

    ```bash
    From: your_email@example.com
    Subject: [YourServerName] IP Address Change Notification

    January 1, 1970 12:30 PM (UTC)

    123.45.67.89
    ```

## License

This project is licensed under the [MIT License](LICENSE).
