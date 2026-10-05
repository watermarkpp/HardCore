"""Fail-closed candidate producer for a deliberately restricted GDScript subset.

No Godot process, Script load, regex path inventory, eval, or project mutation.
This is a dependency producer, not a GDScript parser/semantic validator. A PASS
is only within SUPPORT.md's subset and still needs the normal native/source gate.
The engine namespace and class registration map are explicit fingerprinted inputs.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import unicodedata
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any

PRODUCER = "hc.code_preparation.lexical_subset.candidate.v1"
SCOPE = "supported_gdscript_compile_inputs"
MAX_NODES = 64
MAX_EDGES = 1024
MAX_SOURCE_BYTES = 2097152
MAX_FILE_BYTES = 524288


class Refusal(ValueError):
    pass


@dataclass(frozen=True)
class Token:
    kind: str
    value: str
    line: int
    column: int
    offset: int


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def identifier_start(c: str) -> bool:
    return c == "_" or c.isalpha()


def identifier_part(c: str) -> bool:
    return identifier_start(c) or c.isdigit() or unicodedata.category(c).startswith("M")


def lex(source: str) -> list[Token]:
    """Comments and string contents never become identifier/dependency tokens."""
    tokens: list[Token] = []
    i, line, column = 0, 1, 0
    simple_escapes = {"a": "\a", "b": "\b", "f": "\f", "n": "\n", "r": "\r", "t": "\t", "v": "\v", "\\": "\\", "\"": "\"", "'": "'"}
    while i < len(source):
        c = source[i]
        if c in " \t\r":
            column += 4 if c == "\t" else 1
            i += 1
            continue
        if c == "\n":
            tokens.append(Token("NL", "\n", line, column, i))
            i, line, column = i + 1, line + 1, 0
            continue
        if c == "#":
            while i < len(source) and source[i] != "\n":
                i, column = i + 1, column + 1
            continue
        if c == "\\":
            if source[i:i + 3] == "\\\r\n":
                i, line, column = i + 3, line + 1, 0
            elif source[i:i + 2] == "\\\n":
                i, line, column = i + 2, line + 1, 0
            else:
                raise Refusal(f"unsupported_backslash:{line}:{column}")
            continue
        start, start_line, start_column = i, line, column
        if c in "'\"":
            triple = source.startswith(c * 3, i)
            delimiter = c * (3 if triple else 1)
            i, column = i + len(delimiter), column + len(delimiter)
            value: list[str] = []
            while i < len(source) and not source.startswith(delimiter, i):
                c = source[i]
                if c == "\n":
                    if not triple:
                        raise Refusal(f"newline_in_string:{start_line}:{start_column}")
                    value.append(c)
                    i, line, column = i + 1, line + 1, 0
                    continue
                if c == "\\":
                    if i + 1 >= len(source):
                        raise Refusal(f"unterminated_escape:{line}:{column}")
                    escaped = source[i + 1]
                    if escaped in simple_escapes:
                        value.append(simple_escapes[escaped])
                        i, column = i + 2, column + 2
                    elif escaped in "uU":
                        count = 4 if escaped == "u" else 8
                        digits = source[i + 2:i + 2 + count]
                        if len(digits) != count or any(d not in "0123456789abcdefABCDEF" for d in digits):
                            raise Refusal(f"unsupported_unicode_escape:{line}:{column}")
                        codepoint = int(digits, 16)
                        if codepoint > 0x10FFFF or 0xD800 <= codepoint <= 0xDFFF:
                            raise Refusal(f"unsupported_unicode_scalar:{line}:{column}")
                        value.append(chr(codepoint))
                        i, column = i + count + 2, column + count + 2
                    else:
                        raise Refusal(f"unsupported_string_escape:{line}:{column}:{escaped}")
                    continue
                value.append(c)
                i, column = i + 1, column + 1
            if i >= len(source):
                raise Refusal(f"unterminated_string:{start_line}:{start_column}")
            i, column = i + len(delimiter), column + len(delimiter)
            tokens.append(Token("STRING", "".join(value), start_line, start_column, start))
            continue
        if identifier_start(c):
            i += 1
            while i < len(source) and identifier_part(source[i]):
                i += 1
            value = source[start:i]
            if i < len(source) and source[i] in "'\"" and value in ("r", "R"):
                raise Refusal(f"unsupported_raw_string:{start_line}:{start_column}")
            tokens.append(Token("IDENT", value, start_line, start_column, start))
            column += i - start
            continue
        if c.isdigit():
            i += 1
            while i < len(source) and (source[i].isalnum() or source[i] in "_."):
                i += 1
            tokens.append(Token("NUMBER", source[start:i], start_line, start_column, start))
            column += i - start
            continue
        if c not in "()[]{}.,:+-*/%=<>!&|^~?@$;":
            raise Refusal(f"unsupported_character:{line}:{column}:{ord(c)}")
        tokens.append(Token("SYMBOL", c, line, column, i))
        i, column = i + 1, column + 1
    return tokens


def balanced(tokens: list[Token]) -> dict[int, int]:
    stack: list[int] = []
    matches: dict[int, int] = {}
    for i, token in enumerate(tokens):
        if token.kind != "SYMBOL":
            continue
        if token.value in "([{":
            stack.append(i)
        elif token.value in ")]}":
            if not stack or ("(", "[", "{").index(tokens[stack[-1]].value) != (")", "]", "}").index(token.value):
                raise Refusal(f"unbalanced_delimiter:{token.line}:{token.column}")
            begin = stack.pop()
            matches[begin], matches[i] = i, begin
    if stack:
        token = tokens[stack[-1]]
        raise Refusal(f"unclosed_delimiter:{token.line}:{token.column}")
    return matches


def statement_end(tokens: list[Token], begin: int, pairs: dict[int, int]) -> int:
    i = begin
    while i < len(tokens):
        if tokens[i].kind == "NL" or tokens[i].value == ";":
            return i
        if tokens[i].value in ("(", "[", "{") and tokens[i].kind == "SYMBOL":
            i = pairs[i]
        i += 1
    return i


def normalized_path(value: str, owner: str) -> str:
    if not value or "\\" in value or any(ord(c) < 32 for c in value) or "\x00" in value:
        raise Refusal("invalid_resource_path")
    if value.startswith("res://"):
        relative = value[6:]
    elif ":" not in value and not value.startswith("/"):
        relative = str(PurePosixPath(owner[6:]).parent / value)
    else:
        raise Refusal("unsupported_resource_namespace:" + value)
    parts = relative.split("/")
    if any(part in ("", ".", "..") for part in parts):
        raise Refusal("noncanonical_resource_path:" + value)
    return "res://" + relative


class StringExpression:
    def __init__(self, constants: dict[str, list[Token]]):
        self.constants = constants

    def evaluate(self, expression: list[Token], ancestors: tuple[str, ...] = ()) -> str:
        tokens = [t for t in expression if t.kind != "NL"]
        i = 0

        def term() -> str:
            nonlocal i
            if i >= len(tokens):
                raise Refusal("empty_preload_path_expression")
            token = tokens[i]
            i += 1
            if token.kind == "STRING":
                return token.value
            if token.kind == "IDENT":
                if token.value in ancestors:
                    raise Refusal("cyclic_path_constant:" + token.value)
                if token.value not in self.constants:
                    raise Refusal("unresolved_path_constant:" + token.value)
                return self.evaluate(self.constants[token.value], ancestors + (token.value,))
            if token.value == "(":
                value = expression_value()
                if i >= len(tokens) or tokens[i].value != ")":
                    raise Refusal("unsupported_path_parenthesis")
                i += 1
                return value
            raise Refusal("unsupported_preload_path_expression:" + token.value)

        def expression_value() -> str:
            nonlocal i
            value = term()
            while i < len(tokens) and tokens[i].value == "+":
                i += 1
                value += term()
            return value

        result = expression_value()
        if i != len(tokens):
            raise Refusal("unsupported_preload_path_expression:" + tokens[i].value)
        return result


def extract(source: str, owner: str, global_classes: dict[str, str], native_symbols: set[str], autoloads: dict[str, str], approved_folds: dict[str, dict[str, Any]] | None = None) -> dict[str, Any]:
    tokens = lex(source)
    pairs = balanced(tokens)
    contexts: dict[int, tuple[str, str]] = {}
    eager_function_errors: list[str] = []
    # Top-level methods are not executed by a plain GDScript Resource load.
    # _static_init is the exception; this narrow provider refuses its body.
    # preload remains eager regardless of a token's surrounding method.
    for i, token in enumerate(tokens):
        top_function = token.value == "func" and (token.column == 0 or (i > 0 and tokens[i - 1].value == "static" and tokens[i - 1].column == 0))
        if not top_function:
            continue
        if i + 1 >= len(tokens) or tokens[i + 1].kind != "IDENT":
            eager_function_errors.append(f"unsupported_top_function_header:{token.line}")
            continue
        name = tokens[i + 1].value
        open_index = i + 2
        if open_index not in pairs or tokens[open_index].value != "(":
            eager_function_errors.append(f"unsupported_top_function_header:{token.line}")
            continue
        header_end = pairs[open_index] + 1
        while header_end < len(tokens) and tokens[header_end].kind != "NL" and tokens[header_end].value != ":":
            header_end += 1
        if header_end >= len(tokens) or tokens[header_end].value != ":":
            eager_function_errors.append(f"unsupported_top_function_header:{token.line}")
            continue
        end = header_end + 1
        while end < len(tokens):
            candidate = tokens[end]
            if candidate.kind != "NL" and candidate.column == 0 and candidate.line > tokens[header_end].line:
                break
            end += 1
        phase = "eager_static_init" if name == "_static_init" else "runtime_method"
        if phase == "eager_static_init":
            eager_function_errors.append(f"unsupported_eager_static_init:{token.line}")
        for j in range(i, end):
            contexts[j] = (phase, name)
    for i, token in enumerate(tokens):
        member_var = token.value == "var" and (token.column == 0 or (i > 0 and tokens[i - 1].value == "static" and tokens[i - 1].column == 0))
        if member_var:
            phase = "eager_static_initializer" if i > 0 and tokens[i - 1].value == "static" else "runtime_instance_initializer"
            for j in range(i, statement_end(tokens, i + 1, pairs)):
                contexts[j] = (phase, tokens[i + 1].value if i + 1 < len(tokens) else "")
    constants: dict[str, list[Token]] = {}
    declared: set[str] = set()
    declaration_positions: set[int] = set()
    refusals: list[str] = eager_function_errors
    edges: list[dict[str, Any]] = []
    class_names: list[str] = []
    deferred: list[dict[str, Any]] = []
    class_bindings: list[tuple[str, Token]] = []
    exact_preload_aliases: set[str] = set()
    for i, token in enumerate(tokens):
        if token.kind != "IDENT":
            if token.value == "@":
                refusals.append(f"unsupported_annotation:{token.line}")
            continue
        if token.value in ("class", "enum"):
            refusals.append(f"unsupported_nested_class_or_enum:{token.line}")
        if token.value in ("const", "var", "func", "signal", "class_name") and i + 1 < len(tokens) and tokens[i + 1].kind == "IDENT":
            name = tokens[i + 1].value
            declared.add(name)
            declaration_positions.add(i + 1)
            if token.value == "class_name":
                class_names.append(name)
            if name in global_classes and not (token.value == "class_name" and global_classes[name] == owner):
                class_bindings.append((name, token))
            if name in native_symbols or name in autoloads:
                refusals.append(f"engine_symbol_shadowing:{token.line}:{name}")
            if name[:1].isupper() and token.value not in ("const", "class_name"):
                refusals.append(f"unsupported_uppercase_scoped_binding:{token.line}:{name}")
            if token.value == "const":
                end = statement_end(tokens, i + 2, pairs)
                equal = next((j for j in range(i + 2, end) if tokens[j].value == "="), -1)
                if equal < 0:
                    refusals.append(f"unsupported_constant_declaration:{token.line}")
                elif token.column != 0:
                    refusals.append(f"unsupported_scoped_constant:{token.line}:{name}")
                elif name in constants:
                    refusals.append(f"duplicate_constant:{token.line}:{name}")
                else:
                    constants[name] = tokens[equal + 1:end]
        # Detect all parameter binders so a class name cannot be hidden by an
        # argument. Typed names in the same list remain ordinary reference tokens.
        if token.value in ("func", "signal"):
            open_index = i + 1
            while open_index < len(tokens) and tokens[open_index].kind != "NL" and tokens[open_index].value != "(":
                open_index += 1
            if open_index in pairs:
                at_start = True
                depth = 0
                for j in range(open_index + 1, pairs[open_index]):
                    parameter = tokens[j]
                    if parameter.value in ("(", "[", "{") and parameter.kind == "SYMBOL":
                        depth += 1
                    elif parameter.value in (")", "]", "}") and parameter.kind == "SYMBOL":
                        depth -= 1
                    if depth == 0 and parameter.value == ",":
                        at_start = True
                    elif depth == 0 and at_start and parameter.kind == "IDENT":
                        declared.add(parameter.value)
                        declaration_positions.add(j)
                        at_start = False
                        if parameter.value in global_classes:
                            refusals.append(f"global_class_shadowing:{parameter.line}:{parameter.value}")
                        if parameter.value in native_symbols or parameter.value in autoloads:
                            refusals.append(f"engine_symbol_shadowing:{parameter.line}:{parameter.value}")
                        if parameter.value[:1].isupper():
                            refusals.append(f"unsupported_uppercase_scoped_binding:{parameter.line}:{parameter.value}")
        if token.value == "for" and i + 1 < len(tokens) and tokens[i + 1].kind == "IDENT":
            declared.add(tokens[i + 1].value)
            declaration_positions.add(i + 1)
            if tokens[i + 1].value in global_classes:
                refusals.append(f"global_class_shadowing:{token.line}:{tokens[i + 1].value}")
            if tokens[i + 1].value[:1].isupper():
                refusals.append(f"unsupported_uppercase_scoped_binding:{token.line}:{tokens[i + 1].value}")
        if i + 1 < len(tokens) and tokens[i + 1].value == "(" and token.value in ("load", "load_threaded_request", "load_threaded_get", "instantiate", "call", "callv"):
            phase, method = contexts.get(i, ("unclassified_class_scope", ""))
            deferred.append({"line": token.line, "operation": token.value, "phase": phase, "owner": method,
                             "runtime_resource_contract": "MISSING" if phase.startswith("runtime_") else "NOT_RUN"})
            if not phase.startswith("runtime_"):
                refusals.append(f"unproven_eager_dynamic_execution:{token.line}:{token.value}:{phase}")
        if token.value in ("GDScript", "GDScriptLanguage", "Expression"):
            phase, method = contexts.get(i, ("unclassified_class_scope", ""))
            deferred.append({"line": token.line, "operation": token.value, "phase": phase, "owner": method,
                             "runtime_resource_contract": "MISSING"})
            if not phase.startswith("runtime_"):
                refusals.append(f"unsupported_eager_code_construction:{token.line}:{token.value}")
    if len(class_names) > 1:
        refusals.append("multiple_class_name_declarations")
    evaluator = StringExpression(constants)
    # A top-level alias is safe only when its whole RHS is preload of the exact
    # registered Script path. It grants no permission to shadow a class with a
    # parameter, instance variable, different Script, or computed expression.
    for name, declaration in class_bindings:
        rhs = [t for t in constants.get(name, []) if t.kind != "NL"]
        try:
            if declaration.value != "const" or declaration.column != 0 or len(rhs) < 4 or rhs[0].value != "preload" or rhs[1].value != "(" or rhs[-1].value != ")":
                raise Refusal("not_exact_preload_alias")
            expression = rhs[2:-1]
            if expression and expression[-1].value == ",":
                expression = expression[:-1]
            if normalized_path(evaluator.evaluate(expression), owner) != global_classes[name]:
                raise Refusal("different_registered_path")
            exact_preload_aliases.add(name)
        except Refusal:
            refusals.append(f"global_class_shadowing:{declaration.line}:{name}")
    for name, expression in constants.items():
        approved = (approved_folds or {}).get(owner + "#" + name, {})
        approved_functions = set(approved.get("native_functions", [])) if [t.value for t in expression if t.kind != "NL"] == approved.get("expression_tokens") else set()
        for j, candidate in enumerate(expression):
            following = expression[j + 1].value if j + 1 < len(expression) else ""
            if candidate.kind == "IDENT" and following == "(" and candidate.value not in approved_functions | {"preload", "Vector2", "Vector2i", "Vector3", "Vector3i", "Vector4", "Vector4i", "Rect2", "Rect2i", "Color", "Quaternion", "Transform2D", "Transform3D", "Basis", "Projection", "Plane", "AABB"}:
                refusals.append(f"unsupported_eager_constant_call:{candidate.line}:{name}:{candidate.value}")
            if candidate.value == "(" and j > 0 and expression[j - 1].value in ("]", ")"):
                refusals.append(f"unsupported_indirect_constant_call:{candidate.line}:{name}")
    for i, token in enumerate(tokens):
        if token.kind != "IDENT":
            continue
        if token.value == "preload":
            if i + 1 >= len(tokens) or tokens[i + 1].value != "(":
                refusals.append(f"unsupported_preload_form:{token.line}")
                continue
            end = pairs[i + 1]
            expression = [t for t in tokens[i + 2:end] if t.kind != "NL"]
            if expression and expression[-1].value == ",":
                expression = expression[:-1]
            try:
                path = normalized_path(evaluator.evaluate(expression), owner)
                edges.append({"from": owner, "to": path, "kind": "preload", "line": token.line})
            except Refusal as error:
                refusals.append(f"{error}:{token.line}")
        if token.value == "extends":
            if i + 1 >= len(tokens):
                refusals.append("missing_extends_operand")
                continue
            operand = tokens[i + 1]
            if i + 2 < len(tokens) and tokens[i + 2].value == ".":
                refusals.append(f"unsupported_qualified_extends:{token.line}")
            elif operand.kind == "STRING":
                try:
                    edges.append({"from": owner, "to": normalized_path(operand.value, owner), "kind": "extends_script", "line": token.line})
                except Refusal as error:
                    refusals.append(f"{error}:{token.line}")
            elif operand.kind != "IDENT" or (operand.value not in global_classes and operand.value not in native_symbols):
                refusals.append(f"unresolved_extends_identity:{token.line}:{operand.value}")
        if i in declaration_positions or (i > 0 and tokens[i - 1].value == "."):
            continue
        if token.value in global_classes and token.value not in exact_preload_aliases and global_classes[token.value] != owner:
            edges.append({"from": owner, "to": global_classes[token.value], "kind": "named_class", "line": token.line, "class_name": token.value})
        elif token.value in autoloads:
            edges.append({"from": owner, "to": autoloads[token.value], "kind": "autoload_symbol", "line": token.line, "class_name": token.value})
        elif token.value[:1].isupper() and token.value not in declared and token.value not in native_symbols:
            refusals.append(f"unresolved_global_identity:{token.line}:{token.value}")
    # Nonliteral top-level/static initializers are outside v1 even if they do not
    # contain the token 'load'. This closes the obvious helper-call escape hatch.
    for i, token in enumerate(tokens):
        member_var = token.value == "var" and i > 0 and tokens[i - 1].value == "static" and tokens[i - 1].column == 0
        if not member_var:
            continue
        end = statement_end(tokens, i + 1, pairs)
        equal = next((j for j in range(i + 1, end) if tokens[j].value == "="), -1)
        if equal < 0:
            continue
        intrinsic_values = {"Vector2", "Vector2i", "Vector3", "Vector3i", "Vector4", "Vector4i", "Rect2", "Rect2i", "Color", "Quaternion", "Transform2D", "Transform3D", "Basis", "Projection", "Plane", "AABB"}
        for j in range(equal + 1, end):
            candidate = tokens[j]
            following = tokens[j + 1].value if j + 1 < end else ""
            previous = tokens[j - 1] if j > equal + 1 else None
            if candidate.kind == "IDENT" and following == "(" and candidate.value not in intrinsic_values | {"preload"}:
                refusals.append(f"unsupported_member_initializer_call:{candidate.line}:{candidate.value}")
            if candidate.value == "(" and previous is not None and previous.value in ("]", ")"):
                refusals.append(f"unsupported_indirect_initializer_call:{candidate.line}")
            if candidate.kind == "IDENT" and following == "." and candidate.value not in intrinsic_values:
                refusals.append(f"unsupported_member_initializer_access:{candidate.line}:{candidate.value}")
            if candidate.kind == "IDENT" and (previous is None or previous.value != ".") and candidate.value not in constants and candidate.value not in intrinsic_values | {"preload", "true", "false", "null"}:
                refusals.append(f"unsupported_member_initializer_identity:{candidate.line}:{candidate.value}")
    unique_edges = {json.dumps(edge, sort_keys=True): edge for edge in edges}
    return {"class_name": class_names[0] if len(class_names) == 1 else "", "edges": list(unique_edges.values()),
            "refusals": sorted(set(refusals)), "deferred_observations": deferred}


class VariantData:
    """Only the actual generated class-cache JSON-like Variant data subset."""
    def __init__(self, tokens: list[Token]):
        self.tokens = [t for t in tokens if t.kind != "NL"]
        self.i = 0

    def read(self) -> Any:
        if self.i >= len(self.tokens):
            raise Refusal("class_cache_unexpected_eof")
        token = self.tokens[self.i]
        self.i += 1
        if token.value == "&":
            if self.i >= len(self.tokens) or self.tokens[self.i].kind != "STRING":
                raise Refusal("class_cache_stringname_requires_string")
            return self.read()
        if token.kind == "STRING":
            return token.value
        if token.value in ("true", "false", "null"):
            return {"true": True, "false": False, "null": None}[token.value]
        if token.value == "[":
            result = []
            while self.peek() != "]":
                result.append(self.read())
                if self.peek() == ",":
                    self.i += 1
                elif self.peek() != "]":
                    raise Refusal("class_cache_array_separator")
            self.i += 1
            return result
        if token.value == "{":
            result = {}
            while self.peek() != "}":
                key = self.read()
                if not isinstance(key, str) or key in result or self.peek() != ":":
                    raise Refusal("class_cache_duplicate_or_invalid_key")
                self.i += 1
                result[key] = self.read()
                if self.peek() == ",":
                    self.i += 1
                elif self.peek() != "}":
                    raise Refusal("class_cache_dictionary_separator")
            self.i += 1
            return result
        raise Refusal("class_cache_unsupported_value:" + token.value)

    def peek(self) -> str:
        return self.tokens[self.i].value if self.i < len(self.tokens) else "<eof>"


def read_class_map(data: bytes) -> dict[str, str]:
    tokens = lex(data.decode("utf-8-sig"))
    compact = [t for t in tokens if t.kind != "NL"]
    if len(compact) < 3 or compact[0].value != "list" or compact[1].value != "=":
        raise Refusal("class_cache_header_invalid")
    parser = VariantData(compact[2:])
    entries = parser.read()
    if parser.i != len(parser.tokens) or not isinstance(entries, list):
        raise Refusal("class_cache_trailing_or_invalid_data")
    result: dict[str, str] = {}
    paths: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict) or entry.get("language") != "GDScript" or not isinstance(entry.get("class"), str) or not isinstance(entry.get("path"), str):
            raise Refusal("class_cache_entry_invalid")
        name, path = entry["class"], normalized_path(entry["path"], "res://project.godot")
        if not name[:1].isupper():
            raise Refusal("unsupported_lowercase_global_class:" + name)
        if name in result or path in paths:
            raise Refusal("conflicting_global_class_path:" + name)
        result[name] = path
        paths.add(path)
    return result


def read_autoloads(source: str) -> dict[str, str]:
    active = False
    result = {}
    for line in source.splitlines():
        stripped = line.strip()
        if stripped.startswith("["):
            active = stripped == "[autoload]"
            continue
        if not active or not stripped or stripped.startswith(";"):
            continue
        tokens = [t for t in lex(stripped) if t.kind != "NL"]
        if len(tokens) != 3 or tokens[0].kind != "IDENT" or tokens[1].value != "=" or tokens[2].kind != "STRING":
            raise Refusal("autoload_metadata_unsupported")
        name, value = tokens[0].value, tokens[2].value
        if name in result:
            raise Refusal("duplicate_autoload_identity:" + name)
        result[name] = normalized_path(value.removeprefix("*"), "res://project.godot")
    return result


def native_namespace(envelope: dict[str, Any] | None, expected_binary: str | None, utility_symbols: dict[str, Any] | None = None) -> tuple[set[str], list[str]]:
    if envelope is None:
        return set(), ["MISSING:engine_namespace_capture"]
    if envelope.get("schema_version") != 1 or not isinstance(envelope.get("engine"), dict):
        raise Refusal("engine_namespace_contract_invalid")
    if expected_binary is None or envelope["engine"].get("binary_sha256") != expected_binary:
        raise Refusal("engine_namespace_fingerprint_mismatch_or_unspecified")
    if not isinstance(envelope.get("run_id"), str) or not envelope["run_id"] or not envelope.get("invocation_id") or not envelope.get("source_content_sha256"):
        raise Refusal("engine_namespace_producer_identity_missing")
    objects, values, singletons = envelope.get("object_classes"), envelope.get("variant_type_names"), envelope.get("singletons")
    if not isinstance(objects, list) or not isinstance(values, list) or not isinstance(singletons, list) or any(not isinstance(v, str) for v in objects + values + singletons):
        raise Refusal("engine_namespace_symbols_invalid")
    symbols = set(objects + values + singletons + ["Variant"])
    # ClassDB capture never upgrades a JSON 'global_constants.status=PASS'.
    # A separate source-derived artifact must match the executing engine commit
    # and be byte-bound by the caller's approved --expected-global-symbols SHA.
    if utility_symbols is not None:
        version = envelope["engine"].get("version", {})
        if utility_symbols.get("schema_version") != 1 or not version.get("hash") or utility_symbols.get("engine_commit") != version["hash"]:
            raise Refusal("engine_global_symbols_version_mismatch")
        authority = utility_symbols.get("authority", {})
        if authority.get("kind") != "fixed_engine_source_generated" or not isinstance(authority.get("source_files"), list) or not authority["source_files"] or not isinstance(authority.get("extractor_sha256"), str) or len(authority["extractor_sha256"]) != 64:
            raise Refusal("engine_global_symbols_authority_missing")
        if utility_symbols.get("producer_id") != "hc.code_preparation.native_symbols.compile_probe.candidate.v1" or utility_symbols.get("binary_availability") != "PASS" or utility_symbols.get("engine", {}).get("binary_sha256") != expected_binary:
            raise Refusal("engine_global_symbols_binary_proof_missing_or_mismatched")
        if not utility_symbols.get("run_id") or not utility_symbols.get("invocation_id") or not utility_symbols.get("source_content_sha256") or not utility_symbols.get("candidate_artifact_sha256"):
            raise Refusal("engine_global_symbols_run_binding_missing")
        if any(not isinstance(record, dict) or record.get("commit") != version["hash"] or not isinstance(record.get("sha256"), str) or len(record["sha256"]) != 64 for record in authority["source_files"]):
            raise Refusal("engine_global_symbols_source_binding_invalid")
        expected_names: set[str] = set()
        for field in ("global_functions", "global_constants"):
            values = utility_symbols.get(field)
            if not isinstance(values, list) or any(not isinstance(v, str) or not v.isascii() or not v.isidentifier() or v in expected_names for v in values) or len(set(values)) != len(values):
                raise Refusal("engine_global_symbols_metadata_invalid")
            expected_names.update(values)
        results = utility_symbols.get("probe_results")
        if not isinstance(results, list) or len(results) != len(expected_names):
            raise Refusal("engine_global_symbols_probe_coverage_invalid")
        proved: set[str] = set()
        for result in results:
            if not isinstance(result, dict) or result.get("name") not in expected_names or result["name"] in proved or result.get("status") != "PASS" or result.get("reload_error") != 0 or result.get("method_invocations") != 0:
                raise Refusal("engine_global_symbols_probe_failed_or_duplicate")
            kind = result.get("kind")
            destination = "global_constants" if kind == "global_constant" else "global_functions" if kind == "global_function" else ""
            if not destination or result["name"] not in utility_symbols[destination]:
                raise Refusal("engine_global_symbols_kind_mismatch")
            proved.add(result["name"])
        symbols.update(proved)
    return symbols, []


def approved_constant_folds(native: dict[str, Any] | None, expected_binary: str | None, fold_symbols: dict[str, Any] | None) -> dict[str, dict[str, Any]]:
    if fold_symbols is None:
        return {}
    names, errors = native_namespace(native, expected_binary, fold_symbols)
    if errors or fold_symbols.get("constant_fold_contract") != "PASS" or fold_symbols.get("candidate_producer_id") != "hc.code_preparation.scalar_math_fold_candidates.v1":
        raise Refusal("eager_fold_native_contract_missing")
    sources = fold_symbols["authority"]["source_files"]
    if {Path(row.get("relative_source_path", row.get("path", ""))).name for row in sources} != {"variant_utility.cpp", "math_funcs.h"}:
        raise Refusal("eager_fold_fixed_source_chain_missing")
    for result in fold_symbols["probe_results"]:
        row = result.get("registration", {})
        math = row.get("math_forwarder", {})
        if row.get("resource_materialization_policy") != "scalar_direct_math_forwarder" or row.get("utility_category") != "UTILITY_FUNC_TYPE_MATH" or row.get("argument_type") != "double" or row.get("return_type") != "double" or math.get("name") != result["name"] or math.get("callee") != "std::" + result["name"] or math.get("argument_type") != "double" or math.get("return_type") != "double":
            raise Refusal("eager_fold_scalar_purity_chain_invalid")
    cases = fold_symbols.get("constant_fold_cases")
    if not isinstance(cases, list) or not cases or len(cases) > 32:
        raise Refusal("eager_fold_cases_missing_or_capacity")
    accepted = {}
    for case in cases:
        if not isinstance(case, dict) or case.get("status") != "PASS" or case.get("reload_error") != 0 or case.get("method_invocations") != 0 or case.get("source_current") is not True or case.get("result_type") not in ("float", "int"):
            raise Refusal("eager_fold_case_native_failure")
        expression = case.get("expression_tokens")
        functions = case.get("native_functions")
        if not isinstance(expression, list) or not expression or len(expression) > 64 or any(not isinstance(t, str) for t in expression) or not isinstance(functions, list) or not functions or any(n not in names or n not in fold_symbols["global_functions"] for n in functions):
            raise Refusal("eager_fold_expression_contract_invalid")
        if " ".join(expression) != case.get("expression") or sha(case["expression"].encode()) != case.get("expression_sha256"):
            raise Refusal("eager_fold_expression_hash_mismatch")
        owner = normalized_path(case.get("owner_path", ""), "res://project.godot")
        key = owner + "#" + str(case.get("constant_name", ""))
        if key in accepted or not isinstance(case.get("owner_source_sha256"), str) or len(case["owner_source_sha256"]) != 64:
            raise Refusal("eager_fold_duplicate_or_source_missing")
        accepted[key] = case
    return accepted


def compile_entry(root: Path, entry: str, class_cache: Path, native: dict[str, Any] | None, expected_binary: str | None, max_sources: int, utility_symbols: dict[str, Any] | None = None, fold_symbols: dict[str, Any] | None = None) -> dict[str, Any]:
    root = root.resolve()
    target = normalized_path(entry, "res://project.godot")
    native_names, environment_errors = native_namespace(native, expected_binary, utility_symbols)
    approved_folds = approved_constant_folds(native, expected_binary, fold_symbols)
    if fold_symbols is not None:
        fold_names, _ = native_namespace(native, expected_binary, fold_symbols)
        native_names.update(fold_names)
    cache_bytes = class_cache.read_bytes()
    classes = read_class_map(cache_bytes)
    project_bytes = (root / "project.godot").read_bytes()
    if native is not None and (native.get("global_script_class_cache_sha256") != sha(cache_bytes)
                               or native.get("project_godot_sha256") != sha(project_bytes)):
        raise Refusal("engine_namespace_project_or_class_registration_mismatch")
    autoloads = read_autoloads(project_bytes.decode("utf-8-sig"))
    errors = list(environment_errors)
    nodes: dict[str, Any] = {}
    edges: list[dict[str, Any]] = []
    observations: dict[str, Any] = {}
    residency: dict[str, Any] = {}
    pending = [target]
    visited: set[str] = set()
    while pending:
        path = pending.pop(0)
        if path in visited:
            continue
        visited.add(path)
        if len(visited) > max_sources:
            errors.append("source_capacity_exceeded:" + path)
            break
        disk = (root / path[6:]).resolve()
        if not disk.is_relative_to(root):
            errors.append("resolved_path_escapes_project:" + path)
            continue
        suffix = disk.suffix.lower()
        if suffix not in (".gd", ".gdshader"):
            errors.append("unsupported_resource_format_or_importer:" + path)
            continue
        if not disk.is_file():
            errors.append("missing_exact_dependency:" + path)
            continue
        if disk.stat().st_size > MAX_FILE_BYTES:
            errors.append("source_file_byte_capacity:" + path)
            continue
        data = disk.read_bytes()
        if suffix == ".gdshader":
            # Include syntax needs a shader-specific producer. Fail closed on
            # any directive marker, including comments, rather than miss it.
            if "#" in data.decode("utf-8-sig"):
                errors.append("unsupported_shader_preprocessor:" + path)
            nodes[path] = {"kind": "asset", "type": "Shader", "sha256": sha(data), "bytes": len(data)}
            continue
        nodes[path] = {"kind": "script", "type": "GDScript", "sha256": sha(data), "bytes": len(data)}
        try:
            for key, case in approved_folds.items():
                if key.startswith(path + "#") and case["owner_source_sha256"] != sha(data):
                    raise Refusal("eager_fold_owner_source_changed")
            observation = extract(data.decode("utf-8-sig"), path, classes, native_names, autoloads, approved_folds)
        except (Refusal, UnicodeError) as error:
            errors.append(f"{path}:{error}")
            continue
        observations[path] = observation
        errors.extend(f"{path}:{error}" for error in observation["refusals"])
        declared_name = observation["class_name"]
        if declared_name and classes.get(declared_name) != path:
            errors.append("source_class_registration_mismatch:" + path + ":" + declared_name)
        edges.extend(observation["edges"])
        for edge in observation["edges"]:
            if edge["kind"] == "autoload_symbol":
                resident_path = edge["to"]
                resident_disk = (root / resident_path[6:]).resolve()
                if not resident_disk.is_relative_to(root) or not resident_disk.is_file() or resident_disk.suffix != ".gd":
                    errors.append("autoload_registration_source_untrusted_or_missing:" + resident_path)
                    continue
                if resident_disk.stat().st_size > MAX_FILE_BYTES:
                    errors.append("resident_source_file_byte_capacity:" + resident_path)
                    continue
                digest = sha(resident_disk.read_bytes())
                name = edge["class_name"]
                # This is a required live consumer check, not readiness granted
                # by an offline cache/metadata boolean. Do not recurse through
                # an autoload which the current SceneTree must already own.
                residency[name] = {"kind":"autoload_residency", "autoload_name":name, "script_path":resident_path,
                                   "source_sha256":digest, "stage":"before_code_request", "readiness":"NOT_RUN"}
                if resident_path not in nodes:
                    nodes[resident_path] = {"kind":"resident_script", "type":"GDScript", "sha256":digest, "bytes": resident_disk.stat().st_size}
            else:
                pending.append(edge["to"])
    exact_assets = sorted(path for path, node in nodes.items() if node["kind"] == "asset")
    source_context = {"res://project.godot": {"sha256": sha(project_bytes), "bytes": len(project_bytes)},
                      "res://.godot/global_script_class_cache.cfg": {"sha256": sha(cache_bytes), "bytes": len(cache_bytes)}}
    if any(record["bytes"] > MAX_FILE_BYTES for record in source_context.values()):
        errors.append("authoring_context_file_byte_capacity")
    if len(nodes) > MAX_NODES or len(edges) > MAX_EDGES or sum(node["bytes"] for node in nodes.values()) + len(project_bytes) + len(cache_bytes) > MAX_SOURCE_BYTES:
        errors.append("compiled_graph_node_edge_or_source_byte_capacity")
    errors = sorted(set(errors))
    return {"schema_version": 1, "producer_id": PRODUCER, "scope": SCOPE,
            "status": "MISSING" if any("MISSING:" in e for e in errors) else ("FAIL" if errors else "PASS"),
            "target_path": target, "errors": errors, "nodes": nodes, "edges": edges,
            "observations": observations, "observed_assets": exact_assets,
            "runtime_residency_requirements": sorted(residency.values(), key=lambda requirement: requirement["autoload_name"]),
            "prepared_inputs": [] if errors else exact_assets,
            "source_fingerprints": {"project.godot": sha(project_bytes), "class_cache": sha(cache_bytes),
                                    "source_context": source_context,
                                    "producer": sha(Path(__file__).read_bytes()),
                                    "engine_global_symbols": sha(json.dumps(utility_symbols, sort_keys=True).encode()) if utility_symbols else "MISSING",
                                    "eager_fold_symbols": sha(json.dumps(fold_symbols, sort_keys=True).encode()) if fold_symbols else "MISSING",
                                    "native_namespace": sha(json.dumps(native, sort_keys=True).encode()) if native else "MISSING"},
            "native_execution": "NOT_RUN", "resource_readiness":"NOT_RUN", "publication": "NOT_RUN", "root_complete_preparation": "NOT_RUN"}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--entry", required=True)
    parser.add_argument("--class-cache", type=Path, required=True)
    parser.add_argument("--native-namespace", type=Path)
    parser.add_argument("--expected-engine-binary-sha256")
    parser.add_argument("--global-symbols", type=Path)
    parser.add_argument("--expected-global-symbols-sha256")
    parser.add_argument("--fold-symbols", type=Path)
    parser.add_argument("--expected-fold-symbols-sha256")
    parser.add_argument("--max-source-nodes", type=int, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if args.max_source_nodes <= 0:
        parser.error("--max-source-nodes must be positive; limit refusal is never completeness")
    try:
        native = json.loads(args.native_namespace.read_text(encoding="utf-8")) if args.native_namespace else None
        utility = None
        if args.global_symbols:
            utility_bytes = args.global_symbols.read_bytes()
            if not args.expected_global_symbols_sha256 or sha(utility_bytes) != args.expected_global_symbols_sha256:
                raise Refusal("engine_global_symbols_artifact_hash_mismatch_or_unspecified")
            utility = json.loads(utility_bytes)
        fold = None
        if args.fold_symbols:
            fold_bytes = args.fold_symbols.read_bytes()
            if not args.expected_fold_symbols_sha256 or sha(fold_bytes) != args.expected_fold_symbols_sha256:
                raise Refusal("eager_fold_artifact_hash_mismatch_or_unspecified")
            fold = json.loads(fold_bytes)
        result = compile_entry(args.root, args.entry, args.class_cache, native, args.expected_engine_binary_sha256, args.max_source_nodes, utility, fold)
    except (Refusal, OSError, UnicodeError, ValueError) as error:
        result = {"schema_version": 1, "producer_id": PRODUCER, "status": "FAIL", "errors": [str(error)],
                  "prepared_inputs": [], "native_execution": "NOT_RUN", "publication": "NOT_RUN"}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": result["status"], "errors": len(result["errors"]), "out": str(args.out)}, ensure_ascii=False))
    return 0 if result["status"] == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
