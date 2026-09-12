# Contributing Guidelines

Thank you for your interest in contributing to our project. Whether it's a bug report, new feature, correction, or additional
documentation, we greatly value feedback and contributions from our community.

Please read through this document before submitting any issues or pull requests to ensure we have all the necessary
information to effectively respond to your bug report or contribution.


## Reporting Bugs/Feature Requests

We welcome you to use the GitHub issue tracker to report bugs or suggest features.

When filing an issue, please check existing open, or recently closed, issues to make sure somebody else hasn't already
reported the issue. Please try to include as much information as you can. Details like these are incredibly useful:

* A reproducible test case or series of steps
* The version of our code being used
* Any modifications you've made relevant to the bug
* Anything unusual about your environment or deployment


## Contributing via Pull Requests
Contributions via pull requests are much appreciated. Before sending us a pull request, please ensure that:

1. You are working against the latest source on the *main* branch.
2. You check existing open, and recently merged, pull requests to make sure someone else hasn't addressed the problem already.
3. You open an issue to discuss any significant work - we would hate for your time to be wasted.

To send us a pull request, please:

1. Fork the repository.
2. Modify the source; please focus on the specific change you are contributing. If you also reformat all the code, it will be hard for us to focus on your change.
3. Ensure local tests pass.
4. Commit to your fork using clear commit messages.
5. Send us a pull request, answering any default questions in the pull request interface.
6. Pay attention to any automated CI failures reported in the pull request, and stay involved in the conversation.

GitHub provides additional document on [forking a repository](https://help.github.com/articles/fork-a-repo/) and
[creating a pull request](https://help.github.com/articles/creating-a-pull-request/).


## Finding contributions to work on
Looking at the existing issues is a great way to find something to contribute on. As our projects, by default, use the default GitHub issue labels (enhancement/bug/duplicate/help wanted/invalid/question/wontfix), looking at any 'help wanted' issues is a great place to start.


## Code of Conduct
This project has adopted the [Amazon Open Source Code of Conduct](https://aws.github.io/code-of-conduct).
For more information see the [Code of Conduct FAQ](https://aws.github.io/code-of-conduct-faq) or contact
opensource-codeofconduct@amazon.com with any additional questions or comments.


## Security issue notifications
If you discover a potential security issue in this project we ask that you notify AWS/Amazon Security via our [vulnerability reporting page](http://aws.amazon.com/security/vulnerability-reporting/). Please do **not** create a public github issue.


## Licensing

See the [LICENSE](LICENSE) file for our project's licensing. We will ask you to confirm the licensing of your contribution.

## Checks specific to this sample

Run these before opening a pull request:

```bash
terraform fmt -recursive .
python3 tests/test_encoding.py                    # exporter-side encoding contract
cd modules/placeholder-keys && terraform test     # deployer-side, needs no credentials
cd modules/flow-exporter/lambda/exporter && pylint . --rcfile=../../../../.pylintrc
```

### If you change the placeholder encoding

It must change on **both** sides — `_encode_name()` in the exporter's
`reference_substitutor.py` and `modules/placeholder-keys` — and
`tests/encoding-fixture.json` must be updated with it.

The two sides derive placeholder keys independently and never communicate, so a
one-sided change means no placeholder resolves anywhere. It fails at apply time
in whichever environment applies first, not in review, which is why the contract
is pinned by a fixture asserted from both languages.

## Why there is no CI

Repolinter's default ruleset includes an `integrates-with-ci` check, and this
repository deliberately fails it.

The AWS Samples guidance is explicit that sample code is not a project: *"It
doesn't need a website, it doesn't need CI/CD, and it isn't about building a
community."* A sample is tied to a blog post and is archived when that post
reaches end of life.

A GitHub Actions workflow was added briefly and removed. It pinned tool versions
that drifted from the ones the code was verified against, so it failed on the
first push — a red badge on a published sample is worse than no badge, and worse
than the Repolinter check it existed to satisfy.

Run the checks above locally instead. They need no AWS credentials.
