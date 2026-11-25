package io.mocklane.sdk

/**
 * Internal API shared between `mocklane-core` and its client adapters.
 *
 * Client code should use an adapter facade (`MocklaneOkHttp`, `MocklaneKtor`)
 * instead. This API may change without notice.
 */
@RequiresOptIn(
    message = "Mocklane adapter internal API; use MocklaneOkHttp or MocklaneKtor instead.",
    level = RequiresOptIn.Level.ERROR,
)
@Retention(AnnotationRetention.BINARY)
@Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY,
    AnnotationTarget.CONSTRUCTOR,
)
public annotation class MocklaneInternalApi
