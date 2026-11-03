#!/usr/bin/env python3
"""Observe what Xcode's coremlc makes of Core ML models (.mlmodel, .mlpackage).

Runs on a Mac with Xcode 27.0 (DEVELOPER_DIR) and a Python with coremltools 9.0 (BSD,
`pip install coremltools==9.0`), which writes the models: every model below is built here from
scratch with coremltools' public protobuf classes and builders. For each model it records
`coremlc compile` with the options Swift Build passes (docs/formats/coreml.md), and
`coremlc generate` for each language, with and without `--dry-run yes`, plus one xcodebuild of
an app that compiles the models, for the command lines of CoreMLModelCompile and
CoreMLModelCodegen.

Outputs go to <output-dir>/coreml/observations.json (base64 file contents). Nothing here is
Xcode's own content: only its outputs for these inputs.

Usage: coreml_experiments.py <output-dir> [case ...]
"""

import base64
import json
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
import coremltools as ct
from coremltools.converters.mil import Builder as mb
from coremltools.converters.mil.mil import get_new_symbol, types
from coremltools.models import datatypes
from coremltools.models.neural_network import NeuralNetworkBuilder
from coremltools.proto import FeatureTypes_pb2, Model_pb2

sys.path.insert(0, str(Path(__file__).parent))
import loader_experiments as loader  # noqa: E402

WORK = Path("/tmp/nomac-coreml-experiments")
DEVELOPER = os.environ.get("DEVELOPER_DIR", "/Applications/Xcode_27.app/Contents/Developer")
ARRAY = Model_pb2.ArrayFeatureType


def feature(collection, name, kind, shape=(), data_type=ARRAY.DOUBLE, description=""):
    entry = collection.add()
    entry.name = name
    entry.shortDescription = description
    if kind == "array":
        entry.type.multiArrayType.shape.extend(shape)
        entry.type.multiArrayType.dataType = data_type
    elif kind == "double":
        entry.type.doubleType.SetInParent()
    elif kind == "int64":
        entry.type.int64Type.SetInParent()
    elif kind == "string":
        entry.type.stringType.SetInParent()
    elif kind == "image":
        entry.type.imageType.width, entry.type.imageType.height = shape
        entry.type.imageType.colorSpace = FeatureTypes_pb2.ImageFeatureType.RGB
    elif kind == "dict-string":
        entry.type.dictionaryType.stringKeyType.SetInParent()
    elif kind == "dict-int":
        entry.type.dictionaryType.int64KeyType.SetInParent()
    return entry


def glm(version=1, metadata=False):
    model = Model_pb2.Model()
    model.specificationVersion = version
    feature(model.description.input, "x", "array", [3], description="three numbers" if metadata else "")
    feature(model.description.output, "y", "double")
    model.description.predictedFeatureName = "y"
    weights = model.glmRegressor.weights.add()
    weights.value.extend([1.0, 2.0, 3.0])
    model.glmRegressor.offset.append(0.5)
    if metadata:
        model.description.metadata.shortDescription = "A linear model"
        model.description.metadata.author = "nomac"
        model.description.metadata.license = "MIT"
        model.description.metadata.versionString = "1.2"
        model.description.metadata.userDefined["key"] = "value"
    return model


def classifier():
    model = Model_pb2.Model()
    model.specificationVersion = 1
    feature(model.description.input, "x", "array", [2])
    feature(model.description.output, "label", "int64")
    feature(model.description.output, "probabilities", "dict-int")
    model.description.predictedFeatureName = "label"
    model.description.predictedProbabilitiesName = "probabilities"
    weights = model.glmClassifier.weights.add()
    weights.value.extend([1.0, -1.0])
    model.glmClassifier.offset.append(0.0)
    model.glmClassifier.postEvaluationTransform = Model_pb2.GLMClassifier.Logit
    model.glmClassifier.int64ClassLabels.vector.extend([0, 1])
    return model


def trees():
    from coremltools.models.tree_ensemble import TreeEnsembleRegressor
    builder = TreeEnsembleRegressor(["a", "b"], "target")
    builder.add_branch_node(0, 0, 0, 0.5, "BranchOnValueLessThanEqual", 1, 2)
    builder.add_leaf_node(0, 1, 1.0)
    builder.add_leaf_node(0, 2, 2.0)
    builder.spec.treeEnsembleRegressor.treeEnsemble.numPredictionDimensions = 1
    return builder.spec


def scaler():
    model = Model_pb2.Model()
    model.specificationVersion = 1
    feature(model.description.input, "x", "array", [2])
    feature(model.description.output, "scaled", "array", [2])
    model.scaler.shiftValue.extend([1.0, 2.0])
    model.scaler.scaleValue.extend([0.5, 0.25])
    return model


def pipeline():
    model = Model_pb2.Model()
    model.specificationVersion = 1
    feature(model.description.input, "x", "array", [3])
    feature(model.description.output, "y", "double")
    model.description.predictedFeatureName = "y"
    first = model.pipelineRegressor.pipeline.models.add()
    first.specificationVersion = 1
    feature(first.description.input, "x", "array", [3])
    feature(first.description.output, "scaled", "array", [3])
    first.scaler.shiftValue.extend([0.0, 0.0, 0.0])
    first.scaler.scaleValue.extend([1.0, 1.0, 1.0])
    second = model.pipelineRegressor.pipeline.models.add()
    second.CopyFrom(glm())
    second.description.input[0].name = "scaled"
    second.glmRegressor.weights[0].value[:] = [1.0, 2.0, 3.0]
    return model


def features():
    """A model whose inputs and outputs have each feature type: images, strings, integers,
    dictionaries, optional and flexible features, with descriptions."""
    model = Model_pb2.Model()
    model.specificationVersion = 4
    feature(model.description.input, "image", "image", (64, 32), description="a picture")
    feature(model.description.input, "text", "string")
    count = feature(model.description.input, "count", "int64")
    count.type.isOptional = True
    flexible = feature(model.description.input, "values", "array", [1, 3], data_type=ARRAY.FLOAT32)
    flexible.type.multiArrayType.shapeRange.sizeRanges.add(lowerBound=1, upperBound=-1)
    flexible.type.multiArrayType.shapeRange.sizeRanges.add(lowerBound=3, upperBound=3)
    feature(model.description.output, "scores", "dict-string", description="scores by name")
    feature(model.description.output, "image", "image", (64, 32))
    model.identity.SetInParent()
    return model


def neural_network():
    builder = NeuralNetworkBuilder([("input", datatypes.Array(3))], [("output", datatypes.Array(2))])
    builder.add_inner_product("ip", W=np.arange(6, dtype=np.float32).reshape(2, 3), b=np.array([1, 2], dtype=np.float32),
                              input_channels=3, output_channels=2, has_bias=True, input_name="input", output_name="output")
    return builder.spec


def ml_program(directory, name, target=ct.target.iOS16, weights=6):
    @mb.program(input_specs=[mb.TensorSpec(shape=(1, 3))], opset_version=target)
    def program(x):
        weight = np.arange(weights, dtype=np.float32).reshape(-1, 3)
        y = mb.linear(x=x, weight=weight, bias=np.ones(weight.shape[0], dtype=np.float32))
        return mb.relu(x=y, name="out")
    model = ct.convert(program, convert_to="mlprogram", minimum_deployment_target=target, compute_precision=ct.precision.FLOAT32)
    path = directory / f"{name}.mlpackage"
    model.save(str(path))
    return path


def save(directory, name, spec):
    path = directory / f"{name}.mlmodel"
    ct.utils.save_spec(spec, str(path))
    return path


def models(directory):
    """The models of every case, by name, written into `directory`."""
    directory.mkdir(parents=True, exist_ok=True)
    return {
        "GLM": save(directory, "GLM", glm()),
        "GLMMetadata": save(directory, "GLMMetadata", glm(version=4, metadata=True)),
        "Classifier": save(directory, "Classifier", classifier()),
        "Trees": save(directory, "Trees", trees()),
        "Scaler": save(directory, "Scaler", scaler()),
        "Pipeline": save(directory, "Pipeline", pipeline()),
        "Features": save(directory, "Features", features()),
        "NN": save(directory, "NN", neural_network()),
        "Program": ml_program(directory, "Program"),
        "ProgramLarge": ml_program(directory, "ProgramLarge", weights=3 * 64),
    }


def coremlc(*arguments):
    env = {"PATH": "/usr/bin:/bin", "DEVELOPER_DIR": DEVELOPER, "HOME": os.environ["HOME"], "LANG": "en_US.UTF-8"}
    return subprocess.run(["xcrun", "coremlc", *map(str, arguments)], env=env, capture_output=True, text=True)


def tree(root):
    """Every file under `root`, by relative path, base64."""
    return {str(path.relative_to(root)): base64.b64encode(path.read_bytes()).decode()
            for path in sorted(root.rglob("*")) if path.is_file()}


def sdk():
    return subprocess.run(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], env={"DEVELOPER_DIR": DEVELOPER, "PATH": "/usr/bin:/bin"},
                          capture_output=True, text=True).stdout.strip()


def observe_tools(out):
    """`coremlc compile` and `generate` on every model, with Swift Build's options."""
    inputs = models(WORK / "models")
    sdkroot = sdk()
    results = {}
    for name, model in inputs.items():
        entry = {"input": tree(model) if model.is_dir() else base64.b64encode(model.read_bytes()).decode(), "runs": {}}
        for target in ["13.0", "16.0", "18.0"]:
            output = WORK / "compile" / name / target
            shutil.rmtree(output, ignore_errors=True)
            output.mkdir(parents=True)
            plist = output / f"{name}-CoreMLPartialInfo.plist"
            run = coremlc("compile", model, f"{output}/", "--deployment-target", target, "--sdkroot", sdkroot, "--platform", "ios",
                          "--output-partial-info-plist", plist, "--container", "bundle-resources")
            entry["runs"][f"compile {target}"] = {"status": run.returncode, "stdout": run.stdout, "stderr": run.stderr, "files": tree(output)}
        for language, extra in [("Swift", ["--swift-version", "6"]), ("Swift", ["--swift-version", "5", "--public-access"]),
                                ("Objective-C", [])]:
            for dry in [True, False]:
                output = WORK / "generate" / name / f"{language}{''.join(extra)}{dry}"
                shutil.rmtree(output, ignore_errors=True)
                output.mkdir(parents=True)
                arguments = ["generate", model, f"{output}/"] + (["--dry-run", "yes"] if dry else []) + \
                    ["--deployment-target", "18.0", "--sdkroot", sdkroot, "--platform", "ios", "--language", language] + extra
                run = coremlc(*arguments)
                key = " ".join(["generate", language, *extra] + (["--dry-run"] if dry else []))
                entry["runs"][key] = {"status": run.returncode, "stdout": run.stdout.replace(str(output), "$OUT"),
                                      "stderr": run.stderr, "files": tree(output)}
        results[name] = entry
        print(f"{name}: {len(entry['runs'])} runs")
    return results


SOURCE_TYPES = {".swift": "sourcecode.swift", ".mlmodel": "file.mlmodel", ".mlpackage": "folder.mlpackage"}


def project(names):
    """An iOS app target whose Sources phase has `names` (Swift files and models)."""
    names = sorted(names)
    objects = "".join(f'\t\tA1{index:022d} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = A2{index:022d} /* {name} */; }};\n'
                      f'\t\tA2{index:022d} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {SOURCE_TYPES[Path(name).suffix]}; '
                      f'path = {name}; sourceTree = "<group>"; }};\n' for index, name in enumerate(names))
    children = "".join(f"\t\t\t\tA2{index:022d} /* {name} */,\n" for index, name in enumerate(names))
    phase = "".join(f"\t\t\t\tA1{index:022d} /* {name} in Sources */,\n" for index, name in enumerate(names))
    objects += f"""		F00000000000000000000002 = {{
			isa = PBXGroup;
			children = (
{children}				P00000000000000000000001,
			);
			sourceTree = "<group>";
		}};
		F00000000000000000000004 /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{phase}			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
"""
    settings = {**loader.APP_SETTINGS, "SWIFT_VERSION": "6.0", "IPHONEOS_DEPLOYMENT_TARGET": "18.0"}
    objects += loader.product_file("P00000000000000000000001", "App", loader.APPLICATION)
    objects += loader.app_target("C00000000000000000000001", "App", ["F00000000000000000000004 /* Sources */"],
                                 ["F000000000000000000000TL", "F000000000000000000000TD", "F000000000000000000000TR"], settings,
                                 product_reference="P00000000000000000000001")
    return loader.project("F00000000000000000000006", "F00000000000000000000002", ["C00000000000000000000001 /* App */"], objects)


APP = """import CoreML
import SwiftUI

@main
struct ExperimentApp: App {
    var body: some Scene {
        WindowGroup { Text(String(describing: try? GLM(configuration: MLModelConfiguration()))) }
    }
}
"""


def variant(index, inputs, outputs, metadata=(), version=4):
    """An identity model with these features and these optional metadata fields."""
    model = Model_pb2.Model()
    model.specificationVersion = version
    for name, kind, shape, data_type, optional in inputs:
        entry = feature(model.description.input, name, kind, shape, data_type)
        entry.type.isOptional = optional
    for name, kind, shape, data_type, optional in outputs:
        feature(model.description.output, name, kind, shape, data_type)
    for field in metadata:
        setattr(model.description.metadata, field, f"{field} {index}")
    model.identity.SetInParent()
    return model


def flexible(entry, kind):
    array = entry.type.multiArrayType
    if kind == "range":
        array.shapeRange.sizeRanges.add(lowerBound=1, upperBound=-1)
        array.shapeRange.sizeRanges.add(lowerBound=3, upperBound=3)
    else:
        array.enumeratedShapes.shapes.add(shape=[1, 3])
        array.enumeratedShapes.shapes.add(shape=[2, 3])


def metadata_models(directory):
    """Identity models covering the optional metadata fields and each kind of feature."""
    directory.mkdir(parents=True, exist_ok=True)
    fields = ["shortDescription", "versionString", "author", "license"]
    models = {}
    for mask in range(16):
        chosen = [field for bit, field in enumerate(fields) if mask & (1 << bit)]
        models[f"Meta{mask}"] = variant(mask, [("x", "double", (), ARRAY.DOUBLE, False)], [("y", "double", (), ARRAY.DOUBLE, False)], chosen)
    kinds = {"Int": ("int64", (), ARRAY.DOUBLE), "String": ("string", (), ARRAY.DOUBLE), "DictInt": ("dict-int", (), ARRAY.DOUBLE),
             "DictString": ("dict-string", (), ARRAY.DOUBLE), "Image": ("image", (64, 32), ARRAY.DOUBLE),
             "ArrayDouble": ("array", [3], ARRAY.DOUBLE), "ArrayFloat": ("array", [1, 3], ARRAY.FLOAT32),
             "ArrayInt": ("array", [2, 2], ARRAY.INT32), "ArrayHalf": ("array", [4], ARRAY.FLOAT16)}
    for name, (kind, shape, data_type) in kinds.items():
        for optional in [False, True]:
            models[f"Kind{name}{'Optional' if optional else ''}"] = variant(0, [("x", kind, shape, data_type, optional)], [("y", kind, shape, data_type, False)])
    for shape_kind in ["range", "enumerated"]:
        model = variant(0, [("x", "array", [1, 3], ARRAY.FLOAT32, False)], [("y", "array", [1, 3], ARRAY.FLOAT32, False)])
        flexible(model.description.input[0], shape_kind)
        models[f"Flexible{shape_kind.capitalize()}"] = model
    for size_kind in ["range", "enumerated", "gray"]:
        model = variant(0, [("x", "image", (64, 32), ARRAY.DOUBLE, False)], [("y", "image", (64, 32), ARRAY.DOUBLE, False)])
        image = model.description.input[0].type.imageType
        if size_kind == "range":
            image.imageSizeRange.widthRange.lowerBound, image.imageSizeRange.widthRange.upperBound = 32, 128
            image.imageSizeRange.heightRange.lowerBound, image.imageSizeRange.heightRange.upperBound = 16, -1
        elif size_kind == "enumerated":
            image.enumeratedSizes.sizes.add(width=64, height=32)
            image.enumeratedSizes.sizes.add(width=128, height=64)
        else:
            image.colorSpace = FeatureTypes_pb2.ImageFeatureType.GRAYSCALE
        models[f"Image{size_kind.capitalize()}"] = model
    for element in ["int64", "string"]:
        model = variant(0, [("x", "double", (), ARRAY.DOUBLE, False)], [("y", "double", (), ARRAY.DOUBLE, False)], version=4)
        sequence = model.description.input[0].type
        sequence.Clear()
        getattr(sequence.sequenceType, f"{element}Type").SetInParent()
        sequence.sequenceType.sizeRange.lowerBound = 1
        models[f"Sequence{element.capitalize()}"] = model
    return {name: save(directory, name, spec) for name, spec in models.items()}


def typed(inputs, outputs, version=1):
    model = Model_pb2.Model()
    model.specificationVersion = version
    for name, kind, shape in inputs:
        feature(model.description.input, name, kind, shape)
    for name, kind, shape in outputs:
        feature(model.description.output, name, kind, shape)
    return model


def type_models(directory):
    """One model of each simple type, then an identity model for each specification version."""
    directory.mkdir(parents=True, exist_ok=True)
    models = {}
    model = typed([("x", "array", [2])], [("y", "array", [2])])
    model.normalizer.normType = Model_pb2.Normalizer.L2
    models["TypeNormalizer"] = model
    model = typed([("x", "string", ())], [("y", "array", [2])])
    model.oneHotEncoder.stringCategories.vector.extend(["a", "b"])
    models["TypeOneHot"] = model
    model = typed([("x", "double", ())], [("y", "double", ())])
    model.imputer.imputedDoubleValue = 1.5
    models["TypeImputer"] = model
    model = typed([("a", "double", ()), ("b", "array", [2])], [("y", "array", [3])])
    model.featureVectorizer.inputList.add(inputColumn="a", inputDimensions=1)
    model.featureVectorizer.inputList.add(inputColumn="b", inputDimensions=2)
    models["TypeVectorizer"] = model
    model = typed([("x", "dict-string", ())], [("y", "array", [2])])
    model.dictVectorizer.stringToIndex.vector.extend(["a", "b"])
    models["TypeDictVectorizer"] = model
    model = typed([("x", "string", ())], [("y", "int64", ())])
    model.categoricalMapping.stringToInt64Map.map["a"] = 1
    model.categoricalMapping.int64Value = -1
    models["TypeCategorical"] = model
    model = typed([("x", "array", [3])], [("y", "double", ())])
    model.arrayFeatureExtractor.extractIndex.append(1)
    models["TypeExtractor"] = model
    model = typed([("x", "array", [2])], [("y", "double", ())])
    model.description.predictedFeatureName = "y"
    model.supportVectorRegressor.kernel.linearKernel.SetInParent()
    model.supportVectorRegressor.denseSupportVectors.vectors.add(values=[1.0, 2.0])
    model.supportVectorRegressor.coefficients.alpha.append(0.5)
    model.supportVectorRegressor.rho = 0.1
    models["TypeSVR"] = model
    model = typed([("x", "array", [2])], [("label", "string", ()), ("probabilities", "dict-string", ())])
    model.description.predictedFeatureName = "label"
    model.description.predictedProbabilitiesName = "probabilities"
    weights = model.glmClassifier.weights.add()
    weights.value.extend([1.0, -1.0])
    model.glmClassifier.offset.append(0.0)
    model.glmClassifier.stringClassLabels.vector.extend(["cat", "dog"])
    models["TypeStringClassifier"] = model
    for version in range(1, 10):
        model = typed([("x", "double", ())], [("y", "double", ())], version=version)
        model.identity.SetInParent()
        models[f"Version{version}"] = model
    return {name: save(directory, name, spec) for name, spec in models.items()}


def validation_models(directory, count=60, seed=27):
    """Random simple models nomac's orders were not fitted on: one to four inputs and outputs of
    random kinds, random metadata fields and user entries, identity or GLM, versions 1 to 9."""
    import random
    rnd = random.Random(seed)
    directory.mkdir(parents=True, exist_ok=True)
    kinds = [("double", (), ARRAY.DOUBLE), ("int64", (), ARRAY.DOUBLE), ("string", (), ARRAY.DOUBLE), ("dict-int", (), ARRAY.DOUBLE),
             ("dict-string", (), ARRAY.DOUBLE), ("image", (224, 224), ARRAY.DOUBLE), ("array", [3], ARRAY.DOUBLE),
             ("array", [1, 3], ARRAY.FLOAT32), ("array", [5], ARRAY.INT32)]
    models = {}
    for index in range(count):
        model = Model_pb2.Model()
        model.specificationVersion = rnd.randint(1, 9)
        names = rnd.sample(["input", "image", "text", "features", "value", "a", "b", "logits", "scores", "output_1"], 8)
        for collection, total in [(model.description.input, rnd.randint(1, 4)), (model.description.output, rnd.randint(1, 4))]:
            for _ in range(total):
                kind, shape, data_type = rnd.choice(kinds)
                entry = feature(collection, names.pop(), kind, shape, data_type, description=rnd.choice(["", "A feature", "Größe in cm"]))
                entry.type.isOptional = collection is model.description.input and rnd.random() < 0.3
                if shape == [1, 3] and rnd.random() < 0.5:
                    flexible(entry, rnd.choice(["range", "enumerated"]))
        for field in ["shortDescription", "versionString", "author", "license"]:
            if rnd.random() < 0.5:
                setattr(model.description.metadata, field, rnd.choice(["nomac", "Ünïcode", "a/b \"quoted\"", "1.0"]))
        if rnd.random() < 0.4:
            model.description.metadata.userDefined[rnd.choice(["origin", "com.example.key"])] = rnd.choice(["x", "y/z"])
        model.identity.SetInParent()
        models[f"Validation{index}"] = model
    return {name: save(directory, name, spec) for name, spec in models.items()}


SWIFT_KEYWORDS = """associatedtype borrowing class consuming deinit enum extension fileprivate func import init inout internal let
nonisolated open operator private precedencegroup protocol public rethrows static struct subscript typealias var break case catch
continue default defer do else fallthrough for guard if in repeat return throw switch where while Any as await false is nil self Self
super throws true try async convenience didSet dynamic final get indirect lazy left mutating none nonmutating optional override
package postfix prefix Protocol required right set some Type unowned weak willSet actor any each macro""".split()
OBJC_KEYWORDS = "out bycopy byref oneway id BOOL SEL Class IMP YES NO NULL instancetype".split()
C_KEYWORDS = """auto char const double float goto int long register restrict short signed sizeof unsigned void volatile
union typedef extern bool asm delete friend namespace new operator template this virtual explicit mutable using""".split()
OTHER_NAMES = ["description", "hash", "model", "provider", "featureNames", "featureValue", "input", "output", "options", "input_",
               "configuration", "MLModel", "String", "Double", "_x", "x y", "x-y", "1x", "café", "名前", "x.y", "Out", "OUT"]


def name_models(directory):
    """Identity models whose input has a reserved or unusual name: Swift's keywords, Objective-C's,
    C's and C++'s, names of the generated classes' members, names that are not identifiers."""
    directory.mkdir(parents=True, exist_ok=True)
    models = {}
    for index, name in enumerate(SWIFT_KEYWORDS + OBJC_KEYWORDS + C_KEYWORDS + OTHER_NAMES):
        model = Model_pb2.Model()
        model.specificationVersion = 4
        feature(model.description.input, name, "double")
        feature(model.description.output, "y" if name != "y" else "z", "double")
        model.identity.SetInParent()
        models[f"Name{index}"] = model
    return {name: save(directory, name, spec) for name, spec in models.items()}


def program_models(directory):
    """ML programs: each opset from iOS 15 to 18, both compute precisions, weights inline and in a
    blob file, operations whose arguments are lists, booleans, strings and scalars of each type,
    several inputs and outputs, flexible shapes, and a model without user metadata."""
    directory.mkdir(parents=True, exist_ok=True)
    programs = {}
    for target, label in [(ct.target.iOS15, "15"), (ct.target.iOS16, "16"), (ct.target.iOS17, "17"), (ct.target.iOS18, "18")]:
        for precision, precision_label in [(ct.precision.FLOAT32, "F32"), (ct.precision.FLOAT16, "F16")]:
            @mb.program(input_specs=[mb.TensorSpec(shape=(1, 3))], opset_version=target)
            def linear(x):
                y = mb.linear(x=x, weight=np.arange(6, dtype=np.float32).reshape(2, 3), bias=np.ones(2, dtype=np.float32))
                return mb.relu(x=y, name="out")
            programs[f"ProgLinear{label}{precision_label}"] = (linear, target, precision)

    @mb.program(input_specs=[mb.TensorSpec(shape=(1, 4)), mb.TensorSpec(shape=(1, 4))], opset_version=ct.target.iOS16)
    def arguments(a, b):
        c = mb.concat(values=[a, b], axis=1, interleave=False)
        d = mb.slice_by_index(x=c, begin=[0, 1], end=[1, 7], stride=[1, 2], begin_mask=[True, False], end_mask=[False, False])
        e = mb.reshape(x=d, shape=[3, 1])
        f = mb.cast(x=e, dtype="int32")
        g = mb.cast(x=f, dtype="fp32")
        h = mb.mul(x=g, y=np.float32(0.5))
        i = mb.softmax(x=h, axis=0, name="probabilities")
        j = mb.reduce_sum(x=c, axes=[1], keep_dims=True, name="total")
        return i, j
    programs["ProgArguments"] = (arguments, ct.target.iOS16, ct.precision.FLOAT32)

    @mb.program(input_specs=[mb.TensorSpec(shape=(1, 3, 8, 8))], opset_version=ct.target.iOS17)
    def convolution(x):
        weight = np.random.RandomState(1).rand(4, 3, 3, 3).astype(np.float32)
        y = mb.conv(x=x, weight=weight, strides=[1, 1], pad_type="same", dilations=[1, 1], groups=1)
        z = mb.max_pool(x=y, kernel_sizes=[2, 2], strides=[2, 2], pad_type="valid")
        return mb.matmul(x=mb.reshape(x=z, shape=[1, 64]), y=np.random.RandomState(2).rand(64, 10).astype(np.float32), transpose_x=False,
                         transpose_y=False, name="logits")
    programs["ProgConvolution"] = (convolution, ct.target.iOS17, ct.precision.FLOAT16)

    @mb.program(input_specs=[mb.TensorSpec(shape=(get_new_symbol(), 3))], opset_version=ct.target.iOS16)
    def flexible(x):
        return mb.add(x=x, y=np.float32(1.0), name="shifted")
    programs["ProgFlexible"] = (flexible, ct.target.iOS16, ct.precision.FLOAT32)

    models = {}
    for name, (program, target, precision) in programs.items():
        flexible_input = [ct.TensorType(name="x", shape=(ct.RangeDim(1, 32), 3))] if name == "ProgFlexible" else None
        model = ct.convert(program, convert_to="mlprogram", minimum_deployment_target=target, compute_precision=precision, inputs=flexible_input)
        model.user_defined_metadata.clear() if name == "ProgFlexible" else None
        path = directory / f"{name}.mlpackage"
        model.save(str(path))
        models[name] = path
    return models


def operations(v, m, i, fp):
    """Builder calls for one operation each, on a 1x4x8x8 tensor `v`, a 2x6 matrix `m` and an int32
    vector `i`; `fp` makes a float32 constant."""
    unary = ["abs", "ceil", "cos", "cosh", "erf", "exp", "exp2", "floor", "round", "rsqrt", "sign", "sin", "sinh", "sqrt", "square",
             "tan", "tanh", "relu", "relu6", "sigmoid", "silu", "softsign", "atan"]
    calls = {name: (lambda name=name: getattr(mb, name)(x=m)) for name in unary}
    calls.update({
        "acos": lambda: mb.acos(x=mb.clip(x=m, alpha=fp(-0.5), beta=fp(0.5))),
        "asin": lambda: mb.asin(x=mb.clip(x=m, alpha=fp(-0.5), beta=fp(0.5))),
        "atanh": lambda: mb.atanh(x=mb.clip(x=m, alpha=fp(-0.5), beta=fp(0.5))),
        "log": lambda: mb.log(x=m, epsilon=fp(1e-6)),
        "inverse": lambda: mb.inverse(x=m, epsilon=fp(1e-6)),
        "gelu": lambda: mb.gelu(x=m, mode="EXACT"),
        "elu": lambda: mb.elu(x=m, alpha=fp(1.0)),
        "leaky_relu": lambda: mb.leaky_relu(x=m, alpha=fp(0.1)),
        "softplus": lambda: mb.softplus(x=m),
        "sigmoid_hard": lambda: mb.sigmoid_hard(x=m, alpha=fp(0.2), beta=fp(0.5)),
        "scaled_tanh": lambda: mb.scaled_tanh(x=m, alpha=fp(1.0), beta=fp(1.0)),
        "clamped_relu": lambda: mb.clamped_relu(x=m, alpha=fp(0.1), beta=fp(6.0)),
        "thresholded_relu": lambda: mb.thresholded_relu(x=m, alpha=fp(1.0)),
        "threshold": lambda: mb.threshold(x=m, alpha=fp(0.0)),
        "linear_activation": lambda: mb.linear_activation(x=m, alpha=fp(2.0), beta=fp(1.0)),
        "prelu": lambda: mb.prelu(x=v, alpha=np.ones(4, dtype=np.float32)),
        "softplus_parametric": lambda: mb.softplus_parametric(x=v, alpha=np.ones(4, dtype=np.float32), beta=np.ones(4, dtype=np.float32)),
        "add": lambda: mb.add(x=m, y=m), "sub": lambda: mb.sub(x=m, y=m), "mul": lambda: mb.mul(x=m, y=m),
        "real_div": lambda: mb.real_div(x=m, y=fp(2.0)), "pow": lambda: mb.pow(x=m, y=fp(2.0)),
        "maximum": lambda: mb.maximum(x=m, y=m), "minimum": lambda: mb.minimum(x=m, y=m),
        "floor_div": lambda: mb.floor_div(x=m, y=fp(2.0)), "mod": lambda: mb.mod(x=m, y=fp(2.0)),
        "equal": lambda: mb.equal(x=m, y=m), "not_equal": lambda: mb.not_equal(x=m, y=m), "greater": lambda: mb.greater(x=m, y=m),
        "greater_equal": lambda: mb.greater_equal(x=m, y=m), "less": lambda: mb.less(x=m, y=m), "less_equal": lambda: mb.less_equal(x=m, y=m),
        "logical_not": lambda: mb.logical_not(x=mb.less(x=m, y=fp(0.0))),
        "logical_and": lambda: mb.logical_and(x=mb.less(x=m, y=fp(0.0)), y=mb.greater(x=m, y=fp(1.0))),
        "logical_or": lambda: mb.logical_or(x=mb.less(x=m, y=fp(0.0)), y=mb.greater(x=m, y=fp(1.0))),
        "logical_xor": lambda: mb.logical_xor(x=mb.less(x=m, y=fp(0.0)), y=mb.greater(x=m, y=fp(1.0))),
        "select": lambda: mb.select(cond=mb.less(x=m, y=fp(0.0)), a=m, b=m),
        "clip": lambda: mb.clip(x=m, alpha=fp(0.0), beta=fp(1.0)),
        "cast": lambda: mb.cast(x=m, dtype="int32"),
        "identity": lambda: mb.identity(x=m),
        "reshape": lambda: mb.reshape(x=m, shape=[3, 4]),
        "transpose": lambda: mb.transpose(x=m, perm=[1, 0]),
        "expand_dims": lambda: mb.expand_dims(x=m, axes=[0]),
        "squeeze": lambda: mb.squeeze(x=mb.expand_dims(x=m, axes=[0]), axes=[0]),
        "concat": lambda: mb.concat(values=[m, m], axis=0),
        "stack": lambda: mb.stack(values=[m, m], axis=0),
        "split": lambda: mb.split(x=m, num_splits=2, axis=1),
        "tile": lambda: mb.tile(x=m, reps=[1, 2]),
        "reverse": lambda: mb.reverse(x=m, axes=[1]),
        "slice_by_index": lambda: mb.slice_by_index(x=m, begin=[0, 1], end=[2, 5]),
        "slice_by_size": lambda: mb.slice_by_size(x=m, begin=[0, 1], size=[2, 3]),
        "flatten2d": lambda: mb.flatten2d(x=v, axis=1),
        "shape": lambda: mb.shape(x=m),
        "fill": lambda: mb.fill(shape=[2, 3], value=fp(1.0)),
        "fill_like": lambda: mb.fill_like(ref_tensor=m, value=fp(1.0)),
        "range_1d": lambda: mb.range_1d(start=fp(0.0), end=fp(4.0), step=fp(1.0)),
        "pad": lambda: mb.pad(x=m, pad=[1, 1, 1, 1], mode="constant", constant_val=fp(0.0)),
        "gather": lambda: mb.gather(x=m, indices=i, axis=1),
        "gather_along_axis": lambda: mb.gather_along_axis(x=m, indices=np.zeros((2, 6), dtype=np.int32), axis=1),
        "gather_nd": lambda: mb.gather_nd(x=m, indices=np.zeros((2, 2), dtype=np.int32)),
        "scatter": lambda: mb.scatter(data=m, indices=np.array([0], dtype=np.int32), updates=np.ones((1, 6), dtype=np.float32), axis=0),
        "scatter_along_axis": lambda: mb.scatter_along_axis(data=m, indices=np.zeros((2, 6), dtype=np.int32), updates=m, axis=1),
        "scatter_nd": lambda: mb.scatter_nd(data=m, indices=np.zeros((1, 2), dtype=np.int32), updates=np.ones(1, dtype=np.float32)),
        "one_hot": lambda: mb.one_hot(indices=i, one_hot_vector_size=4),
        "topk": lambda: mb.topk(x=m, k=2, axis=1),
        "argsort": lambda: mb.argsort(x=m, axis=1),
        "cumsum": lambda: mb.cumsum(x=m, axis=1),
        "non_zero": lambda: mb.non_zero(x=m),
        "band_part": lambda: mb.band_part(x=m),
        "reduce_argmax": lambda: mb.reduce_argmax(x=m, axis=1), "reduce_argmin": lambda: mb.reduce_argmin(x=m, axis=1),
        "conv": lambda: mb.conv(x=v, weight=np.ones((2, 4, 3, 3), dtype=np.float32), pad_type="same"),
        "conv_transpose": lambda: mb.conv_transpose(x=v, weight=np.ones((4, 2, 3, 3), dtype=np.float32), pad_type="valid"),
        "avg_pool": lambda: mb.avg_pool(x=v, kernel_sizes=[2, 2], strides=[2, 2], pad_type="valid"),
        "max_pool": lambda: mb.max_pool(x=v, kernel_sizes=[2, 2], strides=[2, 2], pad_type="valid"),
        "l2_pool": lambda: mb.l2_pool(x=v, kernel_sizes=[2, 2], strides=[2, 2], pad_type="valid"),
        "batch_norm": lambda: mb.batch_norm(x=v, mean=np.zeros(4, dtype=np.float32), variance=np.ones(4, dtype=np.float32)),
        "instance_norm": lambda: mb.instance_norm(x=v),
        "layer_norm": lambda: mb.layer_norm(x=m, axes=[1]),
        "l2_norm": lambda: mb.l2_norm(x=m),
        "local_response_norm": lambda: mb.local_response_norm(x=v, size=3),
        "linear": lambda: mb.linear(x=m, weight=np.ones((3, 6), dtype=np.float32)),
        "matmul": lambda: mb.matmul(x=m, y=np.ones((6, 3), dtype=np.float32)),
        "softmax": lambda: mb.softmax(x=m, axis=1),
        "upsample_nearest_neighbor": lambda: mb.upsample_nearest_neighbor(x=v),
        "upsample_bilinear": lambda: mb.upsample_bilinear(x=v),
        "resize_bilinear": lambda: mb.resize_bilinear(x=v, target_size_height=4, target_size_width=4),
        "resize_nearest_neighbor": lambda: mb.resize_nearest_neighbor(x=v, target_size_height=4, target_size_width=4),
        "crop": lambda: mb.crop(x=v, crop_height=[1, 1], crop_width=[1, 1]),
        "depth_to_space": lambda: mb.depth_to_space(x=v, block_size=2),
        "space_to_depth": lambda: mb.space_to_depth(x=v, block_size=2),
        "pixel_shuffle": lambda: mb.pixel_shuffle(x=v, upscale_factor=2),
        "pixel_unshuffle": lambda: mb.pixel_unshuffle(x=v, downscale_factor=np.uint32(2)),
        "sliding_windows": lambda: mb.sliding_windows(x=m, axis=1, size=2),
        "scaled_dot_product_attention": lambda: mb.scaled_dot_product_attention(query=v, key=v, value=v),
    })
    for reduction in ["reduce_l1_norm", "reduce_l2_norm", "reduce_log_sum", "reduce_log_sum_exp", "reduce_max", "reduce_mean", "reduce_min",
                      "reduce_prod", "reduce_sum", "reduce_sum_square"]:
        calls[reduction] = lambda reduction=reduction: getattr(mb, reduction)(x=m, axes=[1])
    return calls


def opset_models(directory):
    """One program per opset from iOS 15 to 18 with every operation `operations` builds that the
    opset has, kept as written (no optimization passes), for the operation names Core ML counts."""
    directory.mkdir(parents=True, exist_ok=True)
    models = {}
    specs = [mb.TensorSpec(shape=(1, 4, 8, 8)), mb.TensorSpec(shape=(2, 6)), mb.TensorSpec(shape=(4,), dtype=types.int32)]
    for target, label in [(ct.target.iOS15, "15"), (ct.target.iOS16, "16"), (ct.target.iOS17, "17"), (ct.target.iOS18, "18")]:
        available = []
        def single(name):
            def build(v, m, i):
                value = operations(v, m, i, np.float32)[name]()
                return tuple(value) if isinstance(value, (list, tuple)) else value
            return build
        for name in operations(None, None, None, np.float32):
            try:
                mb.program(input_specs=specs, opset_version=target)(single(name))
                available.append(name)
            except Exception:
                continue

        @mb.program(input_specs=specs, opset_version=target)
        def program(v, m, i):
            results = []
            calls = operations(v, m, i, np.float32)
            for name in available:
                value = calls[name]()
                results += list(value) if isinstance(value, (list, tuple)) else [value]
            return tuple(results)
        model = ct.convert(program, convert_to="mlprogram", minimum_deployment_target=target, compute_precision=ct.precision.FLOAT32,
                           pass_pipeline=ct.PassPipeline.EMPTY)
        path = directory / f"Opset{label}.mlpackage"
        model.save(str(path))
        models[f"Opset{label}"] = path
    return models


def program_validation_models(directory, count=16, seed=7):
    """Random ML programs nomac was not fitted on: each opset, either precision, five to twelve
    operations of `operations` that every opset has (`opsets`), in random order, weights large
    enough for the blob file, through coremltools' default passes."""
    import random
    rnd = random.Random(seed)
    directory.mkdir(parents=True, exist_ok=True)
    targets = [ct.target.iOS15, ct.target.iOS16, ct.target.iOS17, ct.target.iOS18]
    specs = [mb.TensorSpec(shape=(1, 4, 8, 8)), mb.TensorSpec(shape=(2, 6)), mb.TensorSpec(shape=(4,), dtype=types.int32)]
    models = {}
    for index in range(count):
        target = rnd.choice(targets)
        everywhere = sorted(set(operations(None, None, None, np.float32)) - {"fill_like", "pixel_unshuffle", "scaled_dot_product_attention"})
        chosen = rnd.sample(everywhere, rnd.randint(5, 12))

        @mb.program(input_specs=specs, opset_version=target)
        def program(v, m, i):
            calls = operations(v, m, i, np.float32)
            results = [mb.linear(x=m, weight=np.random.RandomState(index).rand(40, 6).astype(np.float32), name="projected")]
            for name in chosen:
                value = calls[name]()
                results += list(value) if isinstance(value, (list, tuple)) else [value]
            return tuple(results)
        precision = rnd.choice([ct.precision.FLOAT16, ct.precision.FLOAT32])
        try:
            model = ct.convert(program, convert_to="mlprogram", minimum_deployment_target=target, compute_precision=precision)
        except Exception as error:
            print(f"ProgramValidation{index}: coremltools does not convert it: {type(error).__name__}")
            continue
        path = directory / f"ProgramValidation{index}.mlpackage"
        model.save(str(path))
        models[f"ProgramValidation{index}"] = path
    return models


def observe_metadata(out, cases="metadata"):
    """metadata.json and the archives of each metadata model, compiled once."""
    sdkroot = sdk()
    results = {}
    builders = {"metadata": metadata_models, "types": type_models, "validation": validation_models, "names": name_models,
                "programs": program_models, "opsets": opset_models, "program-validation": program_validation_models}
    for name, model in builders[cases](WORK / f"{cases}-models").items():
        output = WORK / "metadata" / name
        shutil.rmtree(output, ignore_errors=True)
        output.mkdir(parents=True)
        run = coremlc("compile", model, f"{output}/", "--deployment-target", "18.0", "--sdkroot", sdkroot, "--platform", "ios",
                      "--output-partial-info-plist", output / "partial.plist", "--container", "bundle-resources")
        results[name] = {"input": tree(model) if model.is_dir() else base64.b64encode(model.read_bytes()).decode(), "status": run.returncode, "stderr": run.stderr,
                         "files": tree(output / f"{name}.mlmodelc"), "generated": {}}
        for variant in [["--swift-version", "6.0"], ["--swift-version", "5.0"], ["--swift-version", "5.0", "--public-access"], ["Objective-C"]]:
            generated = WORK / "generated" / name
            shutil.rmtree(generated, ignore_errors=True)
            generated.mkdir(parents=True)
            run = coremlc("generate", model, generated, "--deployment-target", "18.0", "--sdkroot", sdkroot, "--platform", "ios",
                          "--output-partial-info-plist", output / "partial.plist", "--container", "bundle-resources", "--language",
                          *(variant if variant == ["Objective-C"] else ["Swift", *variant]))
            results[name]["generated"][" ".join(variant)] = {"status": run.returncode, "stderr": run.stderr, "files": tree(generated)}
    print(f"{cases}: {len(results)} models, {sum(r['status'] != 0 for r in results.values())} refused")
    return results


def observe_build(out):
    """The CoreML tasks of one Release build, their command lines and what they write."""
    source = WORK / "app"
    shutil.rmtree(source, ignore_errors=True)
    inputs = models(source)
    (source / "App.swift").write_text(APP)
    (source / "P.xcodeproj").mkdir()
    (source / "P.xcodeproj/project.pbxproj").write_text(project(["App.swift", *(path.name for path in inputs.values())]))
    derived = WORK / "DerivedData"
    shutil.rmtree(derived, ignore_errors=True)
    env = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": os.environ["HOME"], "DEVELOPER_DIR": DEVELOPER, "LANG": "en_US.UTF-8"}
    proc = subprocess.run(["xcodebuild", "-project", "P.xcodeproj", "-scheme", "App", "-configuration", "Release", "-destination",
                           "generic/platform=iOS", "-derivedDataPath", str(derived), "CODE_SIGNING_ALLOWED=NO", "build"],
                          cwd=source, env=env, capture_output=True, text=True)
    tasks = []
    for block in proc.stdout.split("\n\n"):
        lines = block.splitlines()
        if lines and lines[0].startswith("CoreML"):
            command = next(line.strip() for line in lines[1:] if "coremlc" in line)
            argv = shlex.split(command)
            argv = argv[next(index for index, argument in enumerate(argv) if argument.endswith("/coremlc")):]
            tasks.append({"rule": lines[0].replace(str(derived), "$DERIVED").replace(str(source), "$SRC"),
                          "argv": [argument.replace(str(derived), "$DERIVED").replace(str(source), "$SRC") for argument in argv]})
    products = derived / "Build/Products/Release-iphoneos/App.app"
    generated = derived / "Build/Intermediates.noindex/P.build/Release-iphoneos/App.build/DerivedSources/CoreMLGenerated"
    errors = sorted({line.replace(str(source), "$SRC") for line in proc.stdout.splitlines() if "error:" in line})
    result = {"status": proc.returncode, "errors": errors, "tasks": tasks,
              "app": {name: files for name, files in tree(products).items() if "mlmodelc" in name or name == "Info.plist"},
              "generated": tree(generated) if generated.exists() else {}}
    shutil.rmtree(derived, ignore_errors=True)
    print(f"build: xcodebuild exit {proc.returncode}, {len(tasks)} CoreML tasks")
    return result


def main():
    out = Path(sys.argv[1]) / "coreml"
    out.mkdir(parents=True, exist_ok=True)
    cases = sys.argv[2:] or ["tools", "metadata", "types", "validation", "names", "programs", "opsets", "program-validation", "build"]
    path = out / "observations.json"
    observations = json.loads(path.read_text()) if path.exists() else {}
    version = subprocess.run(["what", "-q", subprocess.run(["xcrun", "-f", "coremlc"], env={"DEVELOPER_DIR": DEVELOPER, "PATH": "/usr/bin:/bin"},
                                                            capture_output=True, text=True).stdout.strip()], capture_output=True, text=True)
    observations["what"] = version.stdout.strip()
    if "tools" in cases:
        observations["tools"] = observe_tools(out)
    if "metadata" in cases:
        observations["metadata"] = observe_metadata(out)
    for section in ["types", "validation", "names", "programs", "opsets", "program-validation"]:
        if section in cases:
            observations[section] = observe_metadata(out, section)
    if "build" in cases:
        observations["build"] = observe_build(out)
    path.write_text(json.dumps(observations, indent=1, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
