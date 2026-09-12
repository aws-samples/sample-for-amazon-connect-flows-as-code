# Reporting Security Issues

We take all security reports seriously. If you discover a potential security
issue in this project, please notify AWS Security via our
[vulnerability reporting page](https://aws.amazon.com/security/vulnerability-reporting/)
or directly at aws-security@amazon.com.

**Please do not create a public GitHub issue.**

## Scope note for this sample

This is a sample intended for experimentation, not a production deployment.
Two things are worth knowing before you run it:

- IAM policies are scoped to least privilege — Amazon Connect reads are bound to
  the instance ARN and Amazon S3 writes to the environment prefix — but you
  should review them against your own account's requirements.
- No public endpoints are created. There is no Amazon CloudFront distribution
  and no public Amazon API Gateway. The export bucket blocks all public access
  and has server-side encryption enabled.

Deleting resources is covered in the README's cleanup section. Amazon Connect
instance deletion is irreversible, so the sample deliberately creates instances
with generated aliases rather than reusing existing ones.
