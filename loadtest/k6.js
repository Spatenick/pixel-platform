// k6 load test: a realistic mix of uploads and reads.
//   make load-test ENV=dev
// Watch the Grafana dashboard while it runs: the API HPA and the KEDA-scaled
// worker should both scale out, and the SLO panels should stay green.

import http from "k6/http";
import { check, sleep } from "k6";

const BASE_URL = __ENV.BASE_URL || "http://localhost:8080";
const image = open("./sample.jpg", "b");

export const options = {
  scenarios: {
    readers: {
      executor: "ramping-arrival-rate",
      exec: "read",
      startRate: 5,
      timeUnit: "1s",
      preAllocatedVUs: 20,
      maxVUs: 100,
      stages: [
        { duration: "1m", target: 20 },
        { duration: "3m", target: 50 },
        { duration: "1m", target: 0 },
      ],
    },
    uploaders: {
      executor: "ramping-arrival-rate",
      exec: "upload",
      startRate: 1,
      timeUnit: "1s",
      preAllocatedVUs: 10,
      maxVUs: 50,
      stages: [
        { duration: "1m", target: 5 },
        { duration: "3m", target: 15 },
        { duration: "1m", target: 0 },
      ],
    },
  },
  // The same targets as the SLOs -- the test fails if we'd breach them.
  thresholds: {
    "http_req_failed": ["rate<0.005"],
    "http_req_duration{kind:read}": ["p(95)<500"],
    "http_req_duration{kind:upload}": ["p(95)<2000"],
  },
};

export function read() {
  const res = http.get(`${BASE_URL}/v1/images?limit=20`, { tags: { kind: "read" } });
  check(res, { "list ok": (r) => r.status === 200 });
}

export function upload() {
  const res = http.post(
    `${BASE_URL}/v1/images`,
    { file: http.file(image, "sample.jpg", "image/jpeg") },
    { tags: { kind: "upload" } },
  );
  check(res, { "accepted": (r) => r.status === 202 });
  sleep(0.1);
}
