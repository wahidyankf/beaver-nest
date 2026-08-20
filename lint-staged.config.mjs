export default {
  "**/*.{js,jsx,cjs,mjs,ts,tsx,json,json5,css,scss,less,html,md,mdx,yaml,yml,graphql,gql,svg}":
    "prettier --write",
  "apps/bnest-app/**/*.{ex,exs,heex}": () => [
    "npm exec nx run bnest-app:format",
    "npm test",
  ],
};
