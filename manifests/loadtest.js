import http from "k6/http";
import { check, fail } from "k6";

const TRAEFIK_URL = "http://rke2-traefik.kube-system.svc.cluster.local";
const headers = { Host: "api.loadtest.test", "Content-Type": "application/json" };

export const options = {
  systemTags: ["method", "status", "scenario", "expected_response", "name", "check"],
  scenarios: {
    crud: {
      executor: "constant-arrival-rate",
      rate: 10,
      timeUnit: "1s",
      duration: "10m",
      preAllocatedVUs: 10,
      maxVUs: 20,
    },
  },
  thresholds: {
    http_req_failed: [{
      threshold: "rate<0.01",
      abortOnFail: true,
      delayAbortEval: "30s",
    }],
    http_req_duration: [{
      threshold: "p(95)<2000",
      abortOnFail: true,
      delayAbortEval: "60s",
    }],
    checks: ["rate==1"],
    dropped_iterations: ["count==0"],
  },
};

export function setup() {
  const response = http.get(`${TRAEFIK_URL}/healthz`, {
    headers,
    tags: { name: "GET /healthz" },
  });
  if (response.status !== 200) {
    fail(`Traefik health check failed: HTTP ${response.status}`);
  }
}

export default function () {
  const id = `${__VU}-${__ITER}-${Date.now()}`;
  const itemURL = `${TRAEFIK_URL}/items/${id}`;
  const created = http.post(
    `${TRAEFIK_URL}/items`,
    JSON.stringify({ id, value: "created" }),
    { headers, tags: { name: "POST /items" } },
  );
  if (!check(created, { "create returns 201": (r) => r.status === 201 })) {
    return;
  }
  const read = http.get(itemURL, {
    headers, tags: { name: "GET /items/:id" },
  });
  check(read, {
    "read returns stored value": (r) =>
      r.status === 200 && r.json("value") === "created",
  });
  const updated = http.put(itemURL, JSON.stringify({ value: "updated" }), {
    headers, tags: { name: "PUT /items/:id" },
  });
  check(updated, {
    "update returns new value": (r) =>
      r.status === 200 && r.json("value") === "updated",
  });
  const deleted = http.del(itemURL, null, {
    headers, tags: { name: "DELETE /items/:id" },
  });
  check(deleted, { "delete returns 204": (r) => r.status === 204 });
}
