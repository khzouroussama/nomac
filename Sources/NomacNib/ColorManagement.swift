import Foundation

/// The color conversions ibtool gets from CoreGraphics, in its float32 arithmetic (docs/formats/nib.md
/// "Color conversions"). The curves and matrices are what `ColorSyncTransformCopyProperty` reports for
/// each pair of profiles. The power function and its polynomials are fitted on `CGColor` conversions
/// through custom ICC curves, which recover its logarithm and exponential exactly; the whole matches
/// every component of 1.2 million random colors per route and of the `color-grid-*`, `unmatched-grid-*`,
/// `matched-ramp-*` and `sweep-deviceRGB-*` experiments.
enum ColorManagement {
    struct Curve {
        let gamma, a, b, c, d, e: Float

        /// `(a x + b)^gamma + e` from `d` up, `c x` below it, mirrored for negative values.
        func callAsFunction(_ x: Float) -> Float {
            let magnitude = abs(x)
            let value = magnitude >= d ? ColorManagement.power(b.addingProduct(a, magnitude), gamma) + e : c * magnitude
            return x < 0 ? -value : value
        }
    }

    struct Transform {
        let source: Curve
        let matrix: [[Float]]
        let destination: Curve
        /// A destination that is not extended keeps its components within 0 to 1 (`sweep-deviceRGB-*`, `unmatched-grid-*`).
        var clamps = false

        func callAsFunction(_ components: [Float]) -> [Float] {
            let linear = components.map { source($0) }
            return matrix.map { row in
                let product = (row[1] * linear[1]).addingProduct(row[0], linear[0]).addingProduct(row[2], linear[2])
                let value = destination(product)
                return clamps ? min(1, max(0, value)) : value
            }
        }
    }

    static let sRGB = Curve(gamma: 2.4000000953674316, a: 0.9478672742843628, b: 0.05213269963860512, c: 0.07739938050508499, d: 0.040449999272823334, e: 0)
    static let sRGBInverse = Curve(gamma: 0.4166666567325592, a: 1.1371190547943115, b: 0, c: 12.920000076293945, d: 0.003130804980173707, e: -0.054999999701976776)
    static let generic = Curve(gamma: 1.7999999523162842, a: 1, b: 0, c: 0.0625, d: 0.03125, e: 0)
    static let genericInverse = Curve(gamma: 0.5555555820465088, a: 1, b: 0, c: 16, d: 0.001953125, e: 0)

    static let displayP3ToExtendedSRGB = Transform(source: sRGB, matrix: [[1.2250027656555176, -0.22497552633285522, -2.7233185392105952e-05],
                                                                          [-0.042092215269804, 1.042070746421814, 2.146464066754561e-05],
                                                                          [-0.019624916836619377, -0.07860995084047318, 1.0982348918914795]], destination: sRGBInverse)
    static let genericRGBToDisplayP3 = Transform(source: generic, matrix: [[0.8466300964355469, 0.14649412035942078, 0.006875693332403898],
                                                                           [0.052814990282058716, 0.9156515598297119, 0.031533464789390564],
                                                                           [0.01730477064847946, 0.06685251742601395, 0.9158427119255066]], destination: sRGBInverse, clamps: true)
    static let sRGBToDisplayP3 = Transform(source: sRGB, matrix: [[0.8224260807037354, 0.17755700647830963, 1.6891721315914765e-05],
                                                                  [0.0332198292016983, 0.9667982459068298, -1.806962609407492e-05],
                                                                  [0.01707417704164982, 0.07237478345632553, 0.9105510711669922]], destination: sRGBInverse, clamps: true)
    static let sRGBToGenericRGB = Transform(source: sRGB, matrix: [[0.9748595952987671, 0.02729376219213009, -0.0021534189581871033],
                                                                   [-0.020008111372590065, 1.0542303323745728, -0.034222252666950226],
                                                                   [0.001683750539086759, 0.001555427210405469, 0.9967608451843262]], destination: genericInverse, clamps: true)
    static let displayP3ToGenericRGB = Transform(source: sRGB, matrix: [[1.1930991411209106, -0.19070817530155182, -0.002390921348705888],
                                                                        [-0.06821335852146149, 1.1057742834091187, -0.037560902535915375],
                                                                        [-0.01756422407925129, -0.07711326330900192, 1.094677448272705]], destination: genericInverse, clamps: true)

    /// A color's components as CoreGraphics takes them: float32, within 0 to 1 (`converted-range-*`).
    static func input(_ components: [Double]) -> [Float] {
        components.map { min(1, max(0, Float($0))) }
    }

    /// A `calibratedRGB` color of a color-matched document: Generic RGB through Display P3 to
    /// extended sRGB (`color-grid-calibratedRGB`).
    static func calibratedRGB(_ components: [Double]) -> [Float] {
        displayP3ToExtendedSRGB(genericRGBToDisplayP3(input(components)))
    }

    /// A `displayP3` color of a color-matched document (`color-grid-displayP3`).
    static func displayP3(_ components: [Double]) -> [Float] {
        displayP3ToExtendedSRGB(input(components))
    }

    /// A `deviceRGB` color of a color-matched document: sRGB through Display P3 (`sweep-deviceRGB-*`).
    static func deviceRGB(_ components: [Double]) -> [Float] {
        displayP3ToExtendedSRGB(sRGBToDisplayP3(input(components)))
    }

    /// A `calibratedWhite` gray of a color-matched document: Generic Gray to Generic Gray Gamma 2.2,
    /// not clamped but for an opaque gray, which white then names (`matched-ramp-calibratedWhite`, `white-alpha-*`).
    static func calibratedWhite(_ white: Double, alpha: Double) -> Float {
        let value = sRGBInverse(generic(input([white])[0]))
        return alpha == 1 ? min(1, value) : value
    }

    /// A gamma 2.2 gray of a document without color matching: gray on Generic RGB's curve (`unmatched-ramp-*`).
    static func gamma22WhiteToGenericRGB(_ white: Double) -> Float {
        min(1, max(0, genericInverse(sRGB(input([white])[0]))))
    }

    static func power(_ x: Float, _ exponent: Float) -> Float {
        exponential2(exponent * logarithm2(x))
    }

    /// A polynomial per sign of the mantissa's distance from 1, in √½ to √2, even and odd powers apart.
    static func logarithm2(_ x: Float) -> Float {
        var exponent = x.exponent + 1
        var mantissa = x.significand / 2
        if mantissa < 0.70710678118654752 {
            exponent -= 1
            mantissa += mantissa
        }
        let u = mantissa - 1
        let c = u >= 0 ? logarithmAbove : logarithmBelow
        let z = u * u
        let even = c[0].addingProduct(c[2].addingProduct(c[4].addingProduct(c[6], z), z), z)
        let odd = c[1].addingProduct(c[3].addingProduct(c[5], z), z)
        let value = even.addingProduct(u, odd) * u
        return exponent == 0 ? value : Float(exponent) + value
    }

    static func exponential2(_ y: Float) -> Float {
        let whole = y.rounded(.down)
        let fraction = y - whole
        var result = exponential[6]
        for index in stride(from: 5, through: 1, by: -1) {
            result = exponential[index].addingProduct(result, fraction)
        }
        return Float(sign: .plus, exponent: Int(whole), significand: result * fraction + exponential[0])
    }

    private static let logarithmAbove: [Float] = [0x3fb8aa3b, 0xbf38aa06, 0x3ef62766, 0xbeb7a5bf, 0x3e8c16d1, 0xbe383a67, 0x3d8c36cf].map { Float(bitPattern: $0) }
    private static let logarithmBelow: [Float] = [0x3fb8aa3b, 0xbf38a9f3, 0x3ef6559b, 0xbeb66ff3, 0x3ea80bd4, 0xbd7a7ec7, 0x3f126e04].map { Float(bitPattern: $0) }
    private static let exponential: [Float] = [0x3f800000, 0x3f317218, 0x3e75fe20, 0x3d634f9d, 0x3c1e264e, 0x3aa648ee, 0x395a873d].map { Float(bitPattern: $0) }
}
