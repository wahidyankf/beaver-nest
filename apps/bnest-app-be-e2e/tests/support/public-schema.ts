// Exercises every mutation field the public GraphQL schema declares, over HTTP, so a
// scenario can tell whether any of them commits a system message. The fields come from
// the schema's own introspection answer, never from a list kept here. Each field's
// arguments are filled by name from the caller's values; a field with a required argument
// no value names cannot be exercised, and is reported so, never skipped. The application
// test support's `BnestApp.Test.PublicMutationProbe` does the same below HTTP.

export const INTROSPECTION = `{
  __schema {
    mutationType {
      fields {
        name
        args { name type { ...TypeRef } }
        type { ...TypeRef }
      }
    }
  }
}

fragment TypeRef on __Type {
  kind
  name
  ofType { kind name ofType { kind name ofType { kind name } } }
}`;

export interface TypeRef {
  kind: string;
  name: string | null;
  ofType: TypeRef | null;
}

export interface IntrospectionResult {
  __schema: {
    mutationType: {
      fields: {
        name: string;
        args: { name: string; type: TypeRef }[];
        type: TypeRef;
      }[];
    } | null;
  };
}

export interface MutationField {
  name: string;
  args: { name: string; type: string; required: boolean }[];
  selection: string;
}

export type Invocation =
  | { document: string; variables: Record<string, unknown> }
  | { unexercisable: string };

function render(type: TypeRef): string {
  if (type.kind === "NON_NULL" && type.ofType) return `${render(type.ofType)}!`;
  if (type.kind === "LIST" && type.ofType) return `[${render(type.ofType)}]`;
  return type.name ?? "";
}

function selection(type: TypeRef): string {
  if ((type.kind === "NON_NULL" || type.kind === "LIST") && type.ofType)
    return selection(type.ofType);
  return ["OBJECT", "INTERFACE", "UNION"].includes(type.kind)
    ? " { __typename }"
    : "";
}

/** The mutation fields of an introspection answer's `data`. */
export function mutationFields(data: IntrospectionResult): MutationField[] {
  return (data["__schema"].mutationType?.fields ?? []).map((field) => ({
    name: field.name,
    args: field.args.map((arg) => ({
      name: arg.name,
      type: render(arg.type),
      required: arg.type.kind === "NON_NULL",
    })),
    selection: selection(field.type),
  }));
}

/** The document and variables that run `field` with the `values` its arguments name. */
export function invocation(
  field: MutationField,
  values: Record<string, unknown>,
): Invocation {
  const missing = field.args.find(
    (arg) => arg.required && !(arg.name in values),
  );
  if (missing) return { unexercisable: `${field.name}(${missing.name})` };

  const args = field.args.filter((arg) => arg.name in values);
  if (args.length === 0)
    return {
      document: `mutation { ${field.name}${field.selection} }`,
      variables: {},
    };

  const declarations = args
    .map((arg) => `$${arg.name}: ${arg.type}`)
    .join(", ");
  const argumentList = args
    .map((arg) => `${arg.name}: $${arg.name}`)
    .join(", ");
  return {
    document: `mutation(${declarations}) { ${field.name}(${argumentList})${field.selection} }`,
    variables: Object.fromEntries(
      args.map((arg) => [arg.name, values[arg.name]]),
    ),
  };
}

/** Whether a field name mentions a system message, in any letter case. */
export function namesSystem(name: string): boolean {
  return /system/iu.test(name);
}
