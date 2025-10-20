/* functions/.eslintrc.js */
module.exports = {
  root: true,
  env: { node: true, es2022: true },
  extends: [
    "eslint:recommended",
    "plugin:import/recommended",
    "plugin:import/typescript",
    "google",
    "plugin:@typescript-eslint/recommended",
  ],
  parser: "@typescript-eslint/parser",
  parserOptions: {
    project: ["./tsconfig.json", "./tsconfig.dev.json"],
    tsconfigRootDir: __dirname,
    sourceType: "module",
  },
  ignorePatterns: [
    "lib/**/*",              // compiled output
    "generated/**/*",
    "seed-menu.js",          // local utility script
    "seed-menu.prod.cjs",
    ".eslintrc.js",          // don't lint this config file
  ],
  plugins: ["@typescript-eslint", "import"],
  rules: {
    "quotes": ["error", "double"],
    "indent": ["error", 2],
    "import/no-unresolved": "off",

    // So your TS compiles and deploys without busywork:
    "max-len": "off",
    "require-jsdoc": "off",
    "object-curly-spacing": "off",
    "@typescript-eslint/no-explicit-any": "off",
    "@typescript-eslint/no-non-null-assertion": "off",
  },
  overrides: [
    {
      files: ["*.js"],
      env: { node: true, es2022: true },
      rules: { "no-undef": "off" }, // silence module/__dirname in JS utilities
    },
  ],
};
