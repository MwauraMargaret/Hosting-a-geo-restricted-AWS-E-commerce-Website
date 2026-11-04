# Hosting a geo-restricted e-commerce website on AWS

An e-commerce company wants its website on Amazon EC2, a domain name in front of it, and access limited to Africa and Asia. Meridian Market is that shop. Two EC2 instances serve it, CloudFront enforces the continent rule, and Route 53 publishes the domain. A VPN exit in an allowed country loads the shop. A VPN exit anywhere else gets a 403.

## Layout

```text
website/          Storefront: home, shop, cart
infra/            CloudFormation template, instance bootstrap, deploy and teardown
docs/             Architecture, deploy steps, VPN test
diagrams/         Request path
```

## Deploy

You need the AWS CLI, a public Route 53 hosted zone, and a domain whose name servers already point at that zone. The stack runs in us-east-1.

```powershell
.\infra\deploy.ps1 -DomainName shop.example.com -HostedZoneId Z0123456789ABCDEF
```

Details, the console path, and teardown are in [docs/implementation-steps.md](docs/implementation-steps.md). The VPN demonstration is in [docs/vpn-test-plan.md](docs/vpn-test-plan.md).

The load balancer is billed while the stack exists. `.\infra\teardown.ps1` deletes the AWS resources and leaves the domain registration in place.
