import 'dart:convert';
import 'dart:io';
import 'package:http_parser/http_parser.dart';
import 'package:logging/logging.dart';
import 'package:mailer/smtp_server/gmail.dart';
import 'package:mailer/mailer.dart';
import 'package:path/path.dart' as p;
import 'package:smtp/smtp.dart';

main(List<String> args) async {
  hierarchicalLoggingEnabled = true;
  var configFile = new File(
      p.join(p.dirname(p.fromUri(Platform.script)), '..', 'config.json'));
  var config = (!await configFile.exists())
      ? {}
      : await configFile.readAsString().then(json.decode) as Map;
  var address = config['address'] ?? '127.0.0.1';
  var port = config['port'] ?? 587;
  var patterns = (config['patterns'] as List<String> ?? [])
      .map((p) => new RegExp(p.toString()));

  var gmailConfig = config['gmail'] as Map;
  var gmailServer = gmail(gmailConfig['username'], gmailConfig['password']);

  var logger = new Logger('mail_relay')
    ..level = Level.FINEST
    ..onRecord.listen((rec) {
      print('${new DateTime.now()} $rec');
      if (rec.error != null) print(rec.error);
      if (rec.stackTrace != null) print(rec.stackTrace);
    });

  SmtpServer server;

  if (config.containsKey('ssl')) {
    var ssl = config['ssl'] as Map;
    var dirname = p.dirname(configFile.path);
    var ctx = new SecurityContext()
      ..useCertificateChain(p.join(dirname, ssl['chain']))
      ..usePrivateKey(p.join(dirname, ssl['key']));
    server = await SmtpServer.bindSecure(address, port, ctx);
  } else {
    server = await SmtpServer.bind(address, port);
  }

  var uri = new Uri(scheme: 'smtp', host: address, port: port);
  logger.info('SMTP Relay listening at $uri');
  logger.config(config);

  server.mailObjects.listen((mailObject) async {
    for (var pattern in patterns) {
      if (pattern.hasMatch(mailObject.envelope.originatorAddress)) {
        // Relay the message.
        var e = mailObject.envelope;
        var message = new Message()
          ..from = new Address(
              e.originatorAddress, 'Dart Relay from (${e.originatorAddress})')
          ..recipients.addAll(config['recipients'] ?? [])
          ..envelopeFrom = e.originatorAddress
          ..envelopeTos = e.recipientAddresses
          ..subject = 'Relay from $uri: ${e.headers.subject ?? "(no subject)"}';

        var contentType = new MediaType.parse(
            e.headers.contentType?.toString() ?? 'text/plain');

        if (contentType.type == 'text' && contentType.subtype == 'html') {
          // Copy HTML email...
          message.html = mailObject.content;
        } else {
          message.text = mailObject.content;
        }

        try {
          logger.info('Sending to ${message.recipients}...');
          var reports = await send(message, gmailServer);

          for (var report in reports) {
            if (!report.sent) {
              for (var problem in report.validationProblems) {
                logger.warning('Problem #${problem.code}: ${problem.msg}');
              }
            }
          }

          logger.info('Sent to ${message.recipients}');
        } catch (e, st) {
          logger.severe('Relay failure', e, st);
        }

        break;
      }
    }

    mailObject.close();
  });
}
