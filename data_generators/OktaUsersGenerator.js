const fs = require("fs");

const firstNames = [
  "John","Fei","Mahesh","Joseph","Nora","Meena","Jay","Sarah",
  "Liam","Olivia","Noah","Emma","Ava","Sophia","Lucas","Mia",
  "Ethan","Amelia","James","Charlotte","Benjamin","Harper"
];

const lastNames = [
  "Doe","Morales","Surat","Jones","Ward","Das","Kumar","James",
  "Smith","Brown","Taylor","Anderson","Thomas","Jackson",
  "White","Harris","Martin","Thompson","Garcia","Martinez"
];

const titles = [
  "Sales Associate",
  "Finance Manager",
  "Marketing Associate",
  "Sales Manager",
  "Sales Engineer",
  "IT Specialist",
  "Software Engineer",
  "Senior Software Engineer",
  "Engineering Manager",
  "CTO",
  "CEO",
  "HR Manager",
  "Product Manager",
  "Data Analyst"
];

const departments = [
  "Sales",
  "Finance",
  "Marketing",
  "Engineering",
  "IT",
  "HR",
  "Executive",
  "Product",
  "Data"
];

const regions = ["AMER","EMEA","APAC"];

function randomItem(arr){
  return arr[Math.floor(Math.random()*arr.length)];
}

function randomNumber(length){
  return Math.floor(Math.random() * Math.pow(10,length)).toString();
}

function randomId(){
  const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  let id = "00u";
  for(let i=0;i<17;i++){
    id += chars[Math.floor(Math.random()*chars.length)];
  }
  return id;
}

function generateUser(i){

  const firstName = randomItem(firstNames);
  const lastName = randomItem(lastNames);
  const title = randomItem(titles);
  const department = randomItem(departments);
  const region = randomItem(regions);

  const login = `${firstName.toLowerCase()}.${lastName.toLowerCase()}${i}@example.com`;

  return {
    id: randomId(),
    status: "PROVISIONED",
    created: "2025-04-01T11:05:55.000Z",
    activated: "2025-04-01T11:05:55.000Z",
    statusChanged: "2025-04-01T11:05:55.000Z",
    lastLogin: null,
    lastUpdated: "2025-11-10T17:57:25.000Z",
    passwordChanged: null,
    realmId: "guopsfkxeocXq4bHA697",
    type: {
      id: "otypsfkxbi1Cj6oa0697"
    },
    profile: {
      firstName,
      lastName,
      mobilePhone: null,
      costCenter: randomNumber(4),
      secondEmail: null,
      managerId: randomNumber(4),
      title,
      department,
      login,
      region,
      email: login,
      employeeNumber: randomNumber(5)
    },
    credentials: {
      provider: {
        type: "OKTA",
        name: "OKTA"
      }
    },
    _links: {
      self: {
        href: `https://demo-vnaydenova.okta.com/api/v1/users/${randomId()}`
      }
    }
  };
}

const USERS_TO_GENERATE = 5000; // ~50x larger dataset

const users = [];

for(let i=0;i<USERS_TO_GENERATE;i++){
  users.push(generateUser(i));
}

fs.writeFileSync(
  "okta-users.json",
  JSON.stringify(users,null,2)
);

console.log(`Generated ${USERS_TO_GENERATE} users`);