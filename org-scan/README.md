## Welcome

This scans the cloud-gov org in github: https://github.com/cloud-gov

To do a scan:

`./scan_org.sh`

Be sure to document any exceptions in here, the README.md

## Scan Status

2020-05-29: Passing
- cf-ex-wordpress: shows leaks because initial commit, b5e9704a695a7b9607dbc7c10fbf853f53ee8046, isn't whitelisted because of this bug: https://github.com/zricethezav/gitleaks/issues/389


2020-06-17: Warnings

This has a lot of "WARN" messages, but I have reviewed the results from those scans and determined they're all false positives. This is part of closing POA&M CG157 and the report from our 3PAO.

## Exceptions

### cf-drupal-ex

This is fork from the community, and the upstream had defines like:

```php
"define('DB_NAME', 'database_name_here'"
```

that trip gitleaks. We have whitelisted the relevant commits.


### cf-ex-wordpress

This repo had a number of `define` statements in it's history that seem to 
have once been real authenticators:

```
" * define('AUTH_KEY',         ' Xakm<o xQy rw4EMsLKM-?!T+,PFF})H4lzcW57AF0U@N@< >M%G4Yt>f`z]MON');"
" * define('AUTH_SALT',        'eZyT)-Naw]F8CwA*VaW#q*|.)g@o}||wf~@C-YSt}(dh_r6EbI#A,y|nU2{B#JBW');"
" * define('LOGGED_IN_KEY',    '|i|Ux`9<p-h$aFf(qnT:sDO:D1P^wZ$$/Ra@miTJi9G;ddp_<q}6H1)o|a +&JCM');"
" * define('LOGGED_IN_SALT',   '+XSqHc;@Q*K_b|Z?NC[3H!!EONbh.n<+=uKR:>*c(u`g~EJBf#8u#R{mUEZrozmm');"
" * define('NONCE_KEY',        '%:R{[P|,s.KuMltH5}cI;/k<Gx~j!f0I)m_sIyu+&NJZ)-iO>z7X>QYR0Z_XnZ@|');"
" * define('NONCE_SALT',       'h`GXHhD>SLWVfg1(1(N{;.V!MoE(SfbA_ksP@&`+AycHcAV$+?@3q+rxV{%^VyKT');"
" * define('SECURE_AUTH_KEY',  'LzJ}op]mr|6+![P}Ak:uNdJCJZd>(Hx.-Mh#Tz)pCIU#uGEnfFz|f ;;eU%/U^O~');"
" * define('SECURE_AUTH_SALT', '!=oLUTXh,QW=H `}`L|9/^4-3 STz},T(w}W<I`.JjPi)<Bmf1v,HpGe}T1:Xt7n');"
```

and so on.  Those keys were all committed by:

```
     "author": "Daniel Mikusa",
     "email": "dmikusa@gopivotal.com",
```
 
for trial installations in a completely different environment, and don't
reflect any leak for cloud.gov. Even if they were committed by our team, they
were from trial instances that long since been destroyed.

### cg-metrics

This is a fork from https://github.com/MonsantoCo/cf-metrics and the following 
Slack API key was present in the upstream, so it's not one of ours.

```url
https://hooks.slack.com/services/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
```

### cg-s3-service-broker

This is a fork from
https://github.com/cloudfoundry-community/s3-cf-service-broker and the
following AWS (revoked) access key was present in present in upstream, so it's not one
of ours:

```txt
AKIAINI4TNGJWSTZXPUA
```


### cg-landing

Old versions of `_includes/js.html` included a Google Maps API key. On 2020-05-29, John Jediny confirmed the key is no longer valid:

```
src=\"https://maps.googleapis.com/maps/api/js?key=AIzaSyCRngKslUGJTlibkQ3FkfTxj3Xss1UlZDA\u0026sensor=false\"
```

### cg-manifests

There is a file in the repo history at https://github.com/cloud-gov/cg-manifests/blob/staging-uaa/cf/manifest-staging.yml
that has a lot of secrets in it from October 2015 when cloud.gov was in AWS commercial instead of AWS GovCloud. The AWS access key is no longer present in our AWS commercial account, and the entire deployment has long since been torn down. We will whitelist

```
AKIAIEJHTE4VJB2UUR2A
```

### cg-release

There a number of SSH keys in `keys_test.go` that can be ignored:

```javascript
{
	"line": "\t\t\"ssh_host_ecdsa_key\": `-----BEGIN EC PRIVATE KEY-----",
	"offender": "-----BEGIN EC PRIVATE KEY-----",
	"commit": "21800f4263da55dbade9780e788969109f475d86",
	"repo": "cg-release",
	"rule": "EC",
	"commitMessage": "Merge branch 'master' of github.com:cloudfoundry/cf-release\n",
	"author": "Chris Brown and Onsi Fakhouri",
	"email": "pair+cbrown+onsi@pivotallabs.com",
	"file": "src/narc/src/code.google.com/p/go.crypto/ssh/test/keys_test.go",
	"date": "2013-08-21T13:55:01-07:00",
	"tags": "key, EC"
}
```

### cg-site

Peter Burkholder committed a likely fake key, AKIAKAOIAF98HAWE09AW, and it's
confirmed invalid:

```An error occurred (InvalidAccessKeyId) when calling the ListObjectsV2 operation: The AWS Access Key Id you provided does not exist in our records.111
```

### cg-styles

This string, `fb:app_id\" content=\"` causes Facebook false positives. The full line is

```html
<meta property="fb:app_id" content="1401488693436528">
```

which is described at https://developers.facebook.com/docs/sharing/opengraph/using-objects/ and is reference in public html and not a leak.

### cg-uaa

This repo is a fork of https://github.com/cloudfoundry/uaa and includes potential keys from upstream which are not relevant:

```
AKIAIEYGDWG4KUPRZUXA
```

### logsearch-boshrelease

This repo is a fork from https://github.com/cloudfoundry-community/logsearch-boshrelease and
had upstream commits from Pivotal that included a key in https://github.com/cloudfoundry-community/logsearch-boshrelease/blob/fecb5e8ac15a4866971ca2dc0268b133adc1bd7d/config/final.yml that is now revoked: `AKIAIISVJZNKHAZZX3JQ`

There also sample keys in `src/logsearch-config/test/logstash-filters/snippets/redact_passwords-spec.rb`

