# SwiftSMTP

SwiftSMTP provides a SwiftNIO based implementation for sending emails using SMTP servers.

There is the `Configuration` struct (and its nested structs and enums) that configure the access to a SMTP server (hostname, credentials, ...).

Once you have a `Configuration` (together with an NIO EventLoopGroup), you can create a `Mailer`. The mailer is responsible for setting up the NIO channel that connects to the SMTP server and delivers the email.

With a `Mailer` at your disposal, you can use it to send an `Email`. Since SMTP terminates the connection after each delivery, `Mailer` needs to create a new connection per `Email` that is to be delivered.

