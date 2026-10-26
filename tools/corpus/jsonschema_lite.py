"""The subset of JSON Schema that golden.schema.json uses, so the gate needs no third-party package.

validate(value, schema) returns a list of "<path>: <problem>" strings. A keyword outside the subset raises
ValueError, so a schema edit can never be silently ignored.
"""
import re

IGNORED = {"$schema", "title", "description", "$defs", "format"}
TYPES = {
    "object": lambda v: isinstance(v, dict),
    "array": lambda v: isinstance(v, list),
    "string": lambda v: isinstance(v, str),
    "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),
    "number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
    "boolean": lambda v: isinstance(v, bool),
    "null": lambda v: v is None,
}


def validate(value, schema, root=None, path="$"):
    root = schema if root is None else root
    if "$ref" in schema:
        node = root
        for part in schema["$ref"].removeprefix("#/").split("/"):
            node = node[part]
        return validate(value, node, root, path)
    errors = []
    for keyword, rule in schema.items():
        if keyword in IGNORED or keyword == "properties":
            continue
        if keyword == "type":
            names = [rule] if isinstance(rule, str) else rule
            if not any(TYPES[name](value) for name in names):
                return [f"{path}: expected {'|'.join(names)}, got {type(value).__name__}"]
        elif keyword == "enum":
            if value not in rule:
                errors.append(f"{path}: {value!r} is not one of {rule}")
        elif keyword == "const":
            if value != rule:
                errors.append(f"{path}: must be {rule!r}")
        elif keyword == "pattern":
            if isinstance(value, str) and not re.search(rule, value):
                errors.append(f"{path}: {value!r} does not match /{rule}/")
        elif keyword in ("minLength", "minItems"):
            if hasattr(value, "__len__") and len(value) < rule:
                errors.append(f"{path}: {keyword} {rule} violated by {value!r}")
        elif keyword in ("minimum", "maximum", "exclusiveMaximum"):
            if TYPES["number"](value) and {"minimum": value < rule, "maximum": value > rule,
                                           "exclusiveMaximum": value >= rule}[keyword]:
                errors.append(f"{path}: {keyword} {rule} violated by {value!r}")
        elif keyword == "uniqueItems":
            if rule and isinstance(value, list) and len({repr(item) for item in value}) != len(value):
                errors.append(f"{path}: items are not unique")
        elif keyword == "items":
            for index, item in enumerate(value if isinstance(value, list) else []):
                errors += validate(item, rule, root, f"{path}[{index}]")
        elif keyword == "required":
            if isinstance(value, dict):
                errors += [f"{path}: missing required property {name!r}" for name in rule if name not in value]
        elif keyword == "additionalProperties":
            if rule is False and isinstance(value, dict):
                known = schema.get("properties", {})
                errors += [f"{path}: unknown property {name!r}" for name in value if name not in known]
        else:
            raise ValueError(f"unsupported schema keyword {keyword!r} at {path}")
    for name, sub in schema.get("properties", {}).items():
        if isinstance(value, dict) and name in value:
            errors += validate(value[name], sub, root, f"{path}.{name}")
    return errors
