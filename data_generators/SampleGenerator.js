const fs = require("fs");

// read the big file
const users = JSON.parse(fs.readFileSync("okta-users.json", "utf8"));

// shuffle array
const shuffled = users.sort(() => 0.5 - Math.random());

// take 100
const sample = shuffled.slice(0, 100);

// write output
fs.writeFileSync(
    "okta-users_CCCSample.json",
    JSON.stringify(sample, null, 2)
);

console.log("Created okta-users-sample-100.json with 100 random users");