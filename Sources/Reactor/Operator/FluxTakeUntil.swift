import Foundation
import ReactiveStreams

internal class FluxTakeUntilPublisher<T>: Publisher {
  typealias Item = T

  private let predicate: (T) throws -> Bool
  private let source: any Publisher<T>

  init(_ predicate: @escaping (T) throws -> Bool, _ publisher: some Publisher<T>) {
    self.predicate = predicate
    self.source = publisher
  }

  func subscribe(_ subscriber: some Subscriber<Item>) {
    self.source.subscribe(FluxTakeUntilOperator(predicate, subscriber))
  }
}

internal class FluxTakeUntilOperator<T>: Subscriber, Subscription {
  typealias Item = T

  private let predicate: (T) throws -> Bool
  private let actual: any Subscriber<T>

  private var subscription: (any Subscription)?

  private let lock: NSLock = .init()
  private var done: Bool = false

  init(_ predicate: @escaping (T) throws -> Bool, _ actual: any Subscriber<T>) {
    self.predicate = predicate
    self.actual = actual
  }

  func onSubscribe(_ subscription: some ReactiveStreams.Subscription) {
    lock.lock()

    guard self.subscription == nil, !done else {
      lock.unlock()
      self.subscription?.cancel()

      return
    }

    self.subscription = subscription
    lock.unlock()

    actual.onSubscribe(self)
  }

  func onNext(_ element: T) {
    #guardLock(self.lock, self.done, .next)
    actual.onNext(element)

    do {
      if try predicate(element) {
        subscription?.cancel()
        onComplete()

        return
      }
    } catch {
      onError(error)
    }
  }

  func onError(_ error: Error) {
    #guardLock(self.lock, self.done, .terminal)
    actual.onError(error)
  }

  func onComplete() {
    #guardLock(self.lock, self.done, .terminal)
    actual.onComplete()
  }

  func request(_ demand: UInt) {
    subscription?.request(demand)
  }

  func cancel() {
    subscription?.cancel()
  }
}

extension Flux {
  public func takeUntil(_ predicate: @escaping (T) throws -> Bool) -> Flux<T> {
    return Flux(publisher: FluxTakeUntilPublisher(predicate, publisher))
  }
}
