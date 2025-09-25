# ``SwiftSMTPVapor``

SwiftSMTPVapor builds on SwiftSMTP and adds some convenience for using it with Vapor. First, you need to configure SwiftSMTPVapor once at startup. This is usually done in `configure(_:)`. There are multiple ways to configure SwiftSMTP here. The simplest is to use environment variables (see above for details on that):

```swift
/// Initialize SwiftSMTP
app.swiftSMTP.initialize(with: .fromEnvironment())
```

Another way to initialize SwiftSMTP is to use the ``SMTPInitializer`` lifecycle handler:

```swift
/// Initialize SwiftSMTP
app.lifecycle.use(SMTPInitializer(configuration: .fromEnvironment()))
```

The main difference between the two is that with the former, SwiftSMTP is ready to use after the call. The latter will initialize SwiftSMTP during the boot of the Vapor Application. In most cases, this difference doesn't matter and the two are equivalent.

You can of course also provide your own configuration. There are also additional parameters for specifiying the source of the event loop group to use for mailers, the maximum connections for mailers and whether or not to write transmission logs. Usually, those can be left to their defaults.

Next, you can use SwiftSMTP inside a request:

```swift
func handleRequest(_ request: Request) -> EventLoopFuture<Response> {
    let email: Email // created before
    return request.swiftSMTP.mailer.send(email).transform(to: Response())
}
```

This uses the shared mailer, which is lazily initialized. If you need a dedicated mailer, you can use the ``Vapor/Application/SwiftSMTP/createNewMailer()`` method:

```swift
func handleRequest(_ request: Request) -> EventLoopFuture<Response> {
    let email: Email // created before
    return request.swiftSMTP.createNewMailer().send(email).transform(to: Response())
}
```

When using the application's event loop group (which is the default), there will be almost no difference between the two - except maybe for the connection limit. A mailer has a connection limit of two connections by default, which means that a new mailer does not have any connections in its queue.
When using a custom event loop group source, however, creating a new mailer will also create a new event loop group. It's important to keep this in mind, since you're responsible for shutting down that event loop group - whereas SwiftSMTPVapor takes care of shutting down the event loop group of the shared mailer if you use a custom source there.


SwiftSMTP also works with Swift concurrency:

```swift
func handleRequest(_ request: Request) async throws -> Response {
    let email: Email // created before
    try await request.swiftSMTP.mailer.send(email)
    return Response()
}
```
