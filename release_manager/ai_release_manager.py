import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def kubectl(args):
    base = ["kubectl"]
    if os.getenv("KUBECTL_INSECURE", "").lower() == "true":
        base.append("--insecure-skip-tls-verify")
    result = subprocess.run(base + args, check=False, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout.strip()


def http_get(url, timeout=5):
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            body = response.read(512)
            elapsed_ms = (time.perf_counter() - started) * 1000
            return {"ok": 200 <= response.status < 400, "status": response.status, "latency_ms": elapsed_ms, "body": body.decode("utf-8", "ignore")}
    except Exception as exc:
        elapsed_ms = (time.perf_counter() - started) * 1000
        return {"ok": False, "status": 0, "latency_ms": elapsed_ms, "error": str(exc)}


def prometheus_query(prometheus_url, query):
    if not prometheus_url:
        return None
    encoded = urllib.parse.urlencode({"query": query})
    url = f"{prometheus_url.rstrip('/')}/api/v1/query?{encoded}"
    try:
        with urllib.request.urlopen(url, timeout=8) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except Exception:
        return None
    values = payload.get("data", {}).get("result", [])
    if not values:
        return 0.0
    try:
        return float(values[0]["value"][1])
    except (KeyError, ValueError, TypeError, IndexError):
        return None


def set_canary_weight(app, weight, namespace):
    kubectl([
        "-n",
        namespace,
        "annotate",
        "ingress",
        f"{app}-canary",
        f"nginx.ingress.kubernetes.io/canary-weight={weight}",
        "--overwrite",
    ])


def set_canary_image(app, image, namespace):
    kubectl(["-n", namespace, "set", "image", f"deployment/{app}-canary", f"app={image}"])
    kubectl(["-n", namespace, "rollout", "status", f"deployment/{app}-canary", "--timeout=180s"])


def rollback(app, namespace, reason):
    set_canary_weight(app, 0, namespace)
    kubectl(["-n", namespace, "scale", f"deployment/{app}-canary", "--replicas=0"])
    kubectl([
        "-n",
        namespace,
        "annotate",
        f"deployment/{app}-canary",
        f"ai-release.openai.com/last-rollback-reason={reason[:220]}",
        "--overwrite",
    ])


def promote(app, namespace, canary_image):
    kubectl(["-n", namespace, "set", "image", f"deployment/{app}-stable", f"app={canary_image}"])
    kubectl(["-n", namespace, "rollout", "status", f"deployment/{app}-stable", "--timeout=180s"])
    set_canary_weight(app, 0, namespace)
    kubectl(["-n", namespace, "scale", f"deployment/{app}-canary", "--replicas=0"])
    kubectl([
        "-n",
        namespace,
        "annotate",
        f"deployment/{app}-stable",
        "ai-release.openai.com/last-promotion=success",
        "--overwrite",
    ])


def deterministic_score(app, namespace, public_url, prometheus_url):
    health_samples = [http_get(public_url) for _ in range(5)]
    failed = [sample for sample in health_samples if not sample["ok"]]
    p95_latency = sorted(sample["latency_ms"] for sample in health_samples)[int(len(health_samples) * 0.95) - 1]

    restarts = prometheus_query(
        prometheus_url,
        f"sum(increase(kube_pod_container_status_restarts_total{{namespace='{namespace}',pod=~'{app}-canary.*'}}[5m]))",
    )
    unavailable = prometheus_query(
        prometheus_url,
        f"kube_deployment_status_replicas_unavailable{{namespace='{namespace}',deployment='{app}-canary'}}",
    )

    score = 100
    reasons = []
    if failed:
        score -= 45
        reasons.append(f"{len(failed)} health probes failed")
    if p95_latency > 1500:
        score -= 20
        reasons.append(f"p95 probe latency {p95_latency:.0f}ms exceeded 1500ms")
    if restarts and restarts > 0:
        score -= 25
        reasons.append(f"canary pod restarts detected: {restarts}")
    if unavailable and unavailable > 0:
        score -= 30
        reasons.append(f"unavailable canary replicas: {unavailable}")

    return {
        "score": max(score, 0),
        "pass": score >= 90,
        "reasons": reasons or ["deterministic checks passed"],
        "samples": health_samples,
        "prometheus": {"restarts": restarts, "unavailable": unavailable},
    }


def ai_judgment(report):
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        return {"enabled": False}
    model = os.getenv("OPENAI_MODEL", "gpt-4.1-mini")
    prompt = (
        "You are an SRE release manager. Return compact JSON with keys decision "
        "('pass','rollback','watch') and reason. Evaluate this canary report:\n"
        + json.dumps(report, indent=2)
    )
    payload = json.dumps({
        "model": model,
        "messages": [
            {"role": "system", "content": "You make conservative production release decisions."},
            {"role": "user", "content": prompt},
        ],
        "temperature": 0,
    }).encode("utf-8")
    request = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=payload,
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            content = json.loads(response.read().decode("utf-8"))["choices"][0]["message"]["content"]
        return {"enabled": True, "raw": content}
    except (urllib.error.URLError, KeyError, json.JSONDecodeError) as exc:
        return {"enabled": True, "error": str(exc)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True)
    parser.add_argument("--canary-image", required=True)
    parser.add_argument("--public-url", required=True)
    parser.add_argument("--namespace", default="ai-platform")
    parser.add_argument("--weights", default="5,25,50")
    parser.add_argument("--analysis-seconds", type=int, default=30)
    parser.add_argument("--prometheus-url", default=os.getenv("PROMETHEUS_URL", ""))
    args = parser.parse_args()

    weights = [int(weight.strip()) for weight in args.weights.split(",") if weight.strip()]
    print(f"Preparing canary {args.app} with image {args.canary_image}")
    kubectl(["-n", args.namespace, "scale", f"deployment/{args.app}-canary", "--replicas=1"])
    set_canary_image(args.app, args.canary_image, args.namespace)

    reports = []
    for weight in weights:
        print(f"Routing {weight}% traffic to canary")
        set_canary_weight(args.app, weight, args.namespace)
        time.sleep(args.analysis_seconds)
        report = deterministic_score(args.app, args.namespace, args.public_url, args.prometheus_url)
        report["app"] = args.app
        report["weight"] = weight
        report["ai"] = ai_judgment(report)
        reports.append(report)
        print(json.dumps(report, indent=2))
        if not report["pass"]:
            reason = "; ".join(report["reasons"])
            print(f"Canary failed at {weight}%. Rolling back: {reason}", file=sys.stderr)
            rollback(args.app, args.namespace, reason)
            return 2

    print("Canary passed all stages. Promoting stable deployment.")
    promote(args.app, args.namespace, args.canary_image)
    print(json.dumps({"result": "promoted", "reports": reports}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())

