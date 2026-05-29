const js = require("@eslint/js");

module.exports = [
    {
        ignores: ["node_modules/**", "coverage/**", "test/**", "jest.config.js"]
    },
    js.configs.recommended,
    {
        files: ["**/*.js"],
        languageOptions: {
            ecmaVersion: "latest",
            sourceType: "commonjs",
            globals: {
                ...js.configs.recommended.languageOptions?.globals,
                console: "readonly",
                process: "readonly",
                module: "readonly",
                require: "readonly",
                __dirname: "readonly",
                __filename: "readonly",
                setTimeout: "readonly",
                clearTimeout: "readonly",
                setInterval: "readonly",
                clearInterval: "readonly",
                exports: "readonly",
                Buffer: "readonly"
            }
        },
        rules: {
            // Enforce max lines per file to prevent monolithic files and improve maintainability
            "max-lines": ["warn", { "max": 300, "skipBlankLines": true, "skipComments": true }],

            // Enforce max lines per function to encourage smaller, more focused functions
            "max-lines-per-function": ["warn", { "max": 60, "skipBlankLines": true, "skipComments": true, "IIFEs": true }],

            // Detect high complexity (cyclomatic complexity > 10) to keep logic simple and testable
            "complexity": ["warn", 10],

            // Detect deep nesting (max depth > 4) to improve readability and avoid "callback hell" or deeply nested conditions
            "max-depth": ["warn", 4],

            // Detect duplicate imports to clean up the code and avoid redundancy
            "no-duplicate-imports": "warn",

            // General best practices
            "no-unused-vars": ["warn", { 
                "argsIgnorePattern": "^_", 
                "varsIgnorePattern": "^_",
                "caughtErrorsIgnorePattern": "^_"
            }], // Warn on unused variables, ignore those with underscore prefix
            "no-undef": "error" // Error on undefined variables to catch typos and missing imports
        }
    }
];
