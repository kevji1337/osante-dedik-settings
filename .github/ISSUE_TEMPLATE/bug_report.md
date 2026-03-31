---
name: 🐛 Bug Report
description: Create a report to help us improve
title: "[Bug]: "
labels: ["bug"]
body:
  - type: markdown
    attributes:
      value: |
        Thanks for taking the time to fill out this bug report!
  - type: input
    id: contact
    attributes:
      label: Contact Details
      description: How can we get in touch with you if we need more info?
      placeholder: ex. email@example.com
    validations:
      required: false
  - type: textarea
    id: what-happened
    attributes:
      label: What happened?
      description: Also tell us, what did you expect to happen?
      placeholder: Tell us what you see!
      value: "A bug happened!"
    validations:
      required: true
  - type: dropdown
    id: scripts
    attributes:
      label: Which script?
      multiple: true
      options:
        - 01-system-prep.sh
        - 02-ssh-hardening.sh
        - 03-firewall-setup.sh
        - 04-fail2ban-config.sh
        - 05-sysctl-hardening.sh
        - 06-filesystem-security.sh
        - 07-logging-setup.sh
        - 08-monitoring-setup.sh
        - 09-backup-setup.sh
        - 10-docker-security.sh
        - 11-cloudflare-tunnel.sh
        - validate-security.sh
        - check-ufw-docker.sh
    validations:
      required: false
  - type: dropdown
    id: os
    attributes:
      label: What OS are you using?
      multiple: false
      options:
        - Ubuntu 24.04 LTS
        - Ubuntu 22.04 LTS
        - Other Linux
        - Other
    validations:
      required: true
  - type: textarea
    id: logs
    attributes:
      label: Relevant log output
      description: Please copy and paste any relevant log output. This will be automatically formatted into code, so no need for backticks.
      render: shell
  - type: checkboxes
    id: terms
    attributes:
      label: Code of Conduct
      description: By submitting this issue, you agree to follow our [Code of Conduct](CONTRIBUTING.md)
      options:
        - label: I agree to follow this project's Code of Conduct
          required: true
