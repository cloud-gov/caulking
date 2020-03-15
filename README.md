
# How to commit a file with a string that gitleaks objects to:

git config --local hooks.gitleaks false && git commit -am "Slack is in the upstream" && git config --local hooks.gitleaks true
