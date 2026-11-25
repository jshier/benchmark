//
// Copyright (c) 2026 Ordo One AB.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
//
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//

#if canImport(Testing)
import Benchmark
import Foundation
import Testing

@testable import BenchmarkTool

/// A saved baseline is the same bytes for the same results, whatever order the results were collected in, so a
/// baseline kept in version control changes only where its numbers do.
@Suite
struct BaselineEncodingTests {
    private let identifiers = (0..<24).map { BenchmarkIdentifier(target: "Target\($0 % 3)", name: "Benchmark \($0)") }
    private let thresholds = BenchmarkThresholds(
        relative: [.p25: 5.0, .p50: 5.0, .p75: 5.0, .p90: 10.0],
        absolute: [.p50: 3, .p99: 20]
    )

    @Test
    func sameResultsSaveTheSameBytesInAnyOrder() throws {
        let forward = baseline(identifiers)
        let reversed = baseline(identifiers.reversed())

        let first = try forward.storageRepresentation()
        let again = try forward.storageRepresentation()
        #expect(try first == reversed.storageRepresentation())
        #expect(first == again)
    }

    @Test
    func resultsAreSavedInTargetAndNameOrder() throws {
        let data = try baseline(identifiers.shuffled()).storageRepresentation()
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let results = try #require(object["results"] as? [Any])
        // Alternating identifiers and their results, as `Dictionary` encodes keys that aren't strings.
        let saved = stride(from: 0, to: results.count, by: 2).compactMap { index -> String? in
            guard let identifier = results[index] as? [String: String] else { return nil }
            return "\(identifier["target"] ?? "")/\(identifier["name"] ?? "")"
        }
        let expected = identifiers
            .sorted { ($0.target, $0.name) < ($1.target, $1.name) }
            .map { "\($0.target)/\($0.name)" }
        #expect(saved == expected)
    }

    @Test
    func keysAreSorted() throws {
        let data = try baseline(identifiers).storageRepresentation()
        let text = try #require(String(data: data, encoding: .utf8))
        // The top level's keys, then the machine's (each appears once), in sorted order in the text.
        for keys in [["baselineName", "machine", "results"], ["hostname", "kernelVersion", "memory", "processorType", "processors"]] {
            let offsets = try keys.map { key in try #require(text.range(of: "\"\(key)\":")).lowerBound }
            #expect(offsets == offsets.sorted(), "\(keys)")
        }
    }

    @Test
    func savedBaselinesDecode() throws {
        let original = baseline(identifiers)
        let decoded = try JSONDecoder().decode(BenchmarkBaseline.self, from: original.storageRepresentation())

        #expect(decoded.baselineName == original.baselineName)
        #expect(decoded.machine == original.machine)
        #expect(decoded.benchmarkIdentifiers == original.benchmarkIdentifiers)
        for identifier in identifiers {
            let decodedMedians = decoded.results[identifier]?.map { $0.statistics.histogram.valueAtPercentile(50) }
            let originalMedians = original.results[identifier]?.map { $0.statistics.histogram.valueAtPercentile(50) }
            #expect(decodedMedians == originalMedians)
            #expect(decoded.results[identifier]?.first?.thresholds?.relative == original.results[identifier]?.first?.thresholds?.relative)
            #expect(decoded.results[identifier]?.first?.thresholds?.absolute == original.results[identifier]?.first?.thresholds?.absolute)
        }
    }
}

extension BaselineEncodingTests {
    /// A baseline with one result for each identifier, its results dictionary filled in `identifiers`' order.
    private func baseline(_ identifiers: some Sequence<BenchmarkIdentifier>) -> BenchmarkBaseline {
        var results: [BenchmarkIdentifier: [BenchmarkResult]] = [:]
        for identifier in identifiers {
            let statistics = Statistics()
            for sample in 0..<10 {
                statistics.add(1_000 + identifier.name.count * 100 + sample)
            }
            results[identifier] = [
                BenchmarkResult(
                    metric: .wallClock,
                    timeUnits: .nanoseconds,
                    scalingFactor: .one,
                    warmupIterations: 0,
                    thresholds: thresholds,
                    statistics: statistics
                ),
            ]
        }
        let machine = BenchmarkMachine(
            hostname: "host",
            processors: 1,
            processorType: "arm64",
            memory: 1,
            kernelVersion: "1"
        )
        return BenchmarkBaseline(baselineName: "baseline", machine: machine, results: results)
    }
}
#endif
