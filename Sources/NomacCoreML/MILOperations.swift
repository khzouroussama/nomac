/// The names Core ML counts ML program operations under in `metadata.json`'s
/// `mlProgramOperationTypeHistogram`: an operation of an iOS 15 opset program is counted by its
/// type in upper camel case (`SliceByIndex`); in a later opset, under the opset of the last revision
/// of the operation up to the program's (`Ios16.relu` in an iOS 17 program). The revisions of each
/// operation, for programs of the iOS 15, 16, 17 and 18 opsets (0: not in that opset), were read
/// from the histograms of programs with 127 operations (coreml-experiments `opsets`); they are not
/// coremltools' own revisions (`relu` has none after iOS 15 there).
enum MILOperations {
    static let revisions: [String: [Int]] = {
        var table: [String: [Int]] = [:]
        for (revisions, operations) in [
            ([0, 0, 0, 18], ["scaled_dot_product_attention"]),
            ([0, 16, 16, 16], ["fill_like", "pixel_unshuffle"]),
            ([15, 15, 15, 15], ["argsort", "band_part", "crop", "depth_to_space", "fill", "flatten2d", "identity", "non_zero",
                "one_hot", "pad", "pixel_shuffle", "range_1d", "resize_nearest_neighbor", "select", "shape", "space_to_depth",
                "split", "stack", "tile", "upsample_nearest_neighbor"]),
            ([15, 15, 17, 18], ["concat", "expand_dims", "reverse", "slice_by_index", "slice_by_size", "sliding_windows",
                "squeeze", "transpose"]),
            ([15, 16, 16, 16], ["cumsum", "reduce_l1_norm", "reduce_l2_norm", "reduce_log_sum", "reduce_log_sum_exp",
                "reduce_max", "reduce_mean", "reduce_min", "reduce_prod", "reduce_sum", "reduce_sum_square", "resize_bilinear",
                "upsample_bilinear"]),
            ([15, 16, 16, 18], ["avg_pool", "erf", "gelu", "l2_pool", "max_pool", "relu", "relu6", "sigmoid", "silu", "softmax",
                "softplus", "softsign"]),
            ([15, 16, 17, 18], ["abs", "acos", "add", "asin", "atan", "atanh", "batch_norm", "cast", "ceil", "clamped_relu",
                "clip", "conv", "conv_transpose", "cos", "cosh", "elu", "equal", "exp", "exp2", "floor", "floor_div", "gather",
                "gather_along_axis", "gather_nd", "greater", "greater_equal", "instance_norm", "inverse", "layer_norm",
                "leaky_relu", "less", "less_equal", "linear", "linear_activation", "local_response_norm", "log", "logical_and",
                "logical_not", "logical_or", "logical_xor", "matmul", "maximum", "minimum", "mod", "mul", "not_equal", "pow",
                "prelu", "real_div", "reduce_argmax", "reduce_argmin", "reshape", "round", "rsqrt", "scaled_tanh", "scatter",
                "scatter_along_axis", "scatter_nd", "sigmoid_hard", "sign", "sin", "sinh", "softplus_parametric", "sqrt",
                "square", "sub", "tan", "tanh", "threshold", "thresholded_relu", "topk"]),
        ] {
            for operation in operations { table[operation] = revisions }
        }
        return table
    }()

    static let opsetRevisions = ["CoreML5": 0, "CoreML6": 1, "CoreML7": 2, "CoreML8": 3]

    /// The name an operation of type `type` in a program of `opset` is counted under, or `nil` when
    /// it is not observed.
    static func histogramName(_ type: String, opset: String) -> String? {
        guard let index = opsetRevisions[opset], let revision = revisions[type]?[index], revision > 0 else { return nil }
        let parts = type.split(separator: "_").map(String.init)
        let camel = parts[0] + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        return revision == 15 ? camel.prefix(1).uppercased() + camel.dropFirst() : "Ios\(revision).\(camel)"
    }
}
