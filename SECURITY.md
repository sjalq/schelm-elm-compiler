# Security policy

Report suspected vulnerabilities through GitHub's private security advisory
feature for this repository. Do not put exploits, credentials, or private
package URLs in a public issue. Maintainers will assess affected versions and
coordinate disclosure and a fix when warranted.

Only the latest Schelm prerelease is supported. Git package kernel JavaScript
and effect managers are explicitly trusted code, not a sandbox. A malicious
package is not itself a compiler vulnerability unless Schelm violates a stated
boundary, such as accepting application kernel code, ignoring an immutable pin,
or exposing credentials.
