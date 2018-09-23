# mail_relay
Simple Dart executable that runs a simple SMTP server that forwards all
emails to a specified array of `recipients`.

This relay performs no spam checking.

Use the `patterns` configuration to whitelist sender addresses.

Configuration should be in `config.json`:

```json
{
  "gmail": {
    "username": "foo",
    "password": "bar"
  },
  "recipients": ["foo@gmail.com", "bar@gmail.com"],
  "port": 587,
  "address": "0.0.0.0",
  "ssl": {
    "chain": "path/to/chain.pem",
    "key": "path/to/key.pem"
  }
}
```

Then, just run `dart bin/main.dart`.