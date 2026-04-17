# Asesmen KServe untuk Cryptophys Platform

**Tanggal:** 2026-04-14
**Status:** Draft
**Branch:** `claude/assess-kserve-cryptophys-Cgz4D`

---

## Ringkasan Eksekutif

KServe adalah platform serving model ML berbasis Kubernetes yang layak dipertimbangkan untuk Cryptophys. Platform saat ini sudah memiliki fondasi AI/ML yang kuat (Ray, Kueue, MinIO, Harbor, Vault, SPIRE), sehingga KServe dapat diintegrasikan tanpa memulai dari nol. Namun, ada beberapa keputusan arsitektur penting—terutama soal mode deployment (RawDeployment vs Serverless)—yang perlu diputuskan sebelum implementasi dimulai.

**Rekomendasi utama:** Gunakan KServe dalam **RawDeployment mode** untuk menghindari dependensi Knative yang belum ada di platform.

---

## 1. Kondisi Platform Saat Ini

### Infrastruktur ML/AI yang Sudah Ada

| Komponen | Versi | Namespace | Fungsi |
|---|---|---|---|
| KubeRay Operator | v1.5.1 | `flux-system` | Distributed ML compute |
| Ray Cluster | 2.9.0 | `cqls-compute` | AI/General worker groups |
| Kueue | CNCF | `kueue-system` | Job queue & resource quota |
| MinIO | - | `minio-system` | S3-compatible model storage |
| Harbor | - | `registry-system` | Container registry |

### Infrastruktur Pendukung

| Komponen | Fungsi | Relevansi untuk KServe |
|---|---|---|
| Vault | Secret management | Credentials model registry |
| SPIRE | Workload identity | mTLS antar inference service |
| Kyverno | Policy enforcement | Butuh policy exception untuk KServe |
| Envoy Gateway | Gateway API routing | Routing ke inference endpoints |
| Prometheus/Grafana | Observability | Metrics inference latency/throughput |
| Tekton | CI/CD pipeline | Build & push model container images |
| Longhorn | Persistent storage | Model artifact caching lokal |

### Resource Compute yang Tersedia

Ray worker group `ai-workers` (node `nexus-tower`):
- CPU: 4–6 core per pod
- Memory: 8–16 Gi per pod
- Taint: `cryptophys.io/ai-workload=:NoSchedule`
- Autoscale: 1–2 replicas

**Catatan penting:** Tidak ada GPU yang terkonfigurasi di worker specs saat ini. KServe untuk model LLM besar akan membutuhkan GPU; ini perlu dikonfirmasi ke tim ops.

---

## 2. Apa itu KServe

KServe (sebelumnya KFServing) adalah Kubernetes-native model inference platform dari CNCF. Menyediakan:

- **InferenceService CRD**: abstraksi tunggal untuk deploy model dari berbagai framework
- **Pre-built serving runtimes**: TorchServe, TensorFlow Serving, Triton Inference Server, MLflow, XGBoost, Scikit-learn, ONNX, Hugging Face
- **Canary rollouts**: traffic splitting antar versi model
- **Request batching**: menggabungkan request untuk efisiensi GPU/CPU
- **Model explainability**: integrasi dengan Alibi, SHAP
- **Autoscaling**: scale-to-zero (mode Serverless) atau HPA (mode RawDeployment)
- **Multi-model serving**: satu Pod melayani banyak model (ModelMesh)

---

## 3. Dua Mode Deployment KServe

### 3.1 Serverless Mode (Knative-based)

```
InferenceService → Knative Serving → Kourier/Istio → Pod
```

**Kebutuhan tambahan:**
- Knative Serving + Knative Eventing
- Istio atau Kourier sebagai ingress Knative
- Sertifikat TLS untuk Knative

**Keuntungan:**
- Scale-to-zero (efisien resource saat idle)
- Revision-based canary rollout

**Kekurangan untuk cryptophys:**
- Knative **belum ada** di platform — menambah kompleksitas signifikan
- Istio akan overlap/konflik dengan Envoy Gateway yang sudah ada
- 2 komponen besar baru perlu diinstall dan di-maintain
- Kyverno policies perlu banyak penyesuaian untuk Knative pods

**Verdict: TIDAK DISARANKAN** untuk fase pertama

---

### 3.2 RawDeployment Mode (Kubernetes-native)

```
InferenceService → Kubernetes Deployment + Service → Envoy Gateway
```

**Kebutuhan tambahan:**
- Hanya KServe controller + CRDs
- Integrasi dengan Envoy Gateway (sudah ada)

**Keuntungan:**
- Jauh lebih sederhana
- Tidak butuh Knative/Istio
- Kompatibel dengan Kyverno dan kebijakan keamanan yang ada
- HPA untuk autoscaling (standar Kubernetes)
- Mudah diintegrasikan dengan Envoy Gateway via HTTPRoute

**Kekurangan:**
- Tidak bisa scale-to-zero (minimal 1 replica)
- Canary rollout manual via traffic weight di HTTPRoute

**Verdict: DIREKOMENDASIKAN** untuk cryptophys

---

## 4. Analisis Kesesuaian (Fit Analysis)

### 4.1 Kelebihan / Faktor Pendukung

**Infrastruktur compute tersedia:**
- Node `nexus-tower` dengan taint `cryptophys.io/ai-workload` sudah didesain untuk beban AI
- Priority class `cryptophys-ai-workload` (500,000) dapat langsung dipakai InferenceService
- `cqls-compute` namespace dapat dijadikan namespace serving

**Storage model tersedia:**
- MinIO (`minio-system`) adalah S3-compatible storage — KServe mendukung model storage via S3/MinIO out of the box
- Longhorn tersedia untuk persistent volume caching model artifacts

**Registry container tersedia:**
- Harbor (`registry-system`) untuk menyimpan custom serving runtime images
- Tekton pipeline dapat dipakai untuk build & push serving container

**Security framework kompatibel:**
- Vault menyimpan credentials akses MinIO untuk KServe model download
- SPIRE dapat menyediakan workload identity untuk InferenceService pods
- Kyverno mendukung policy exception (sudah ada contoh di `ray/policy-exception.yaml`)

**Observability siap:**
- Prometheus/Grafana stack dapat langsung mengambil metrics inference dari KServe
- KServe mengekspos metrics standar: request rate, latency P50/P90/P99, queue size

**Gateway routing:**
- Envoy Gateway (Gateway API) dapat route traffic ke InferenceService via HTTPRoute
- Support canary via traffic weight di Gateway API

---

### 4.2 Risiko dan Tantangan

#### Risiko 1: Konflik Kyverno Policies
**Tingkat risiko: TINGGI**

KServe controller akan membuat Pods dengan konfigurasi spesifik yang mungkin melanggar policies Kyverno yang ada (memory limits wajib, pod security standards, image pull policy, dll).

**Mitigasi:** Buat `PolicyException` untuk KServe serupa dengan yang ada di `platform/infrastructure/ray/policy-exception.yaml`.

---

#### Risiko 2: Tidak Ada GPU
**Tingkat risiko: TINGGI (jika tujuannya LLM)**

Ray worker specs saat ini hanya CPU (4–6 core, 8–16 Gi). KServe untuk model besar (LLM, diffusion model) butuh GPU.

**Mitigasi:**
- Konfirmasi apakah node `nexus-tower` memiliki GPU (NVIDIA/AMD)
- Jika belum ada GPU, KServe masih bisa dipakai untuk model kecil (scikit-learn, XGBoost, ONNX kecil)
- Tambahkan GPU node pool di cryptophys-genesis untuk eksperimen

---

#### Risiko 3: Tumpang Tindih dengan Ray Serve
**Tingkat risiko: SEDANG**

Ray sudah ada dan Ray Serve juga dapat melakukan model inference. Ada potensi duplikasi fungsi.

**Mitigasi:** Tetapkan pembagian tugas yang jelas:
| Komponen | Use Case |
|---|---|
| **Ray** | Distributed training, preprocessing, batch inference besar, pipeline ML |
| **KServe** | Online serving standar, REST/gRPC inference endpoint, multi-runtime support |

---

#### Risiko 4: Resource Contention di `cqls-compute`
**Tingkat risiko: SEDANG**

Ray dan KServe akan bersaing resource di namespace/node yang sama.

**Mitigasi:**
- Buat namespace terpisah `model-serving` untuk KServe InferenceService
- Gunakan Kueue untuk mengatur resource quota antara Ray dan KServe
- Terapkan LimitRange per namespace

---

#### Risiko 5: Model Versioning & Registry
**Tingkat risiko: RENDAH-SEDANG**

Belum ada model registry (MLflow, BentoML, Seldon) untuk track versi model.

**Mitigasi:**
- MinIO bucket dapat diorganisir secara konvensional: `s3://models/<nama-model>/<versi>/`
- Harbor OCI registry dapat dipakai untuk menyimpan model sebagai OCI artifact (KServe mendukung ini)
- Pertimbangkan MLflow di tahap berikutnya sebagai model registry

---

## 5. Arsitektur yang Diusulkan

### 5.1 Diagram Alur (RawDeployment Mode)

```
[Client Request]
      │
      ▼
[Envoy Gateway] ── HTTPRoute ──► [KServe InferenceService]
                                         │
                              ┌──────────┴──────────┐
                              ▼                     ▼
                    [Predictor Pod]        [Transformer Pod] (opsional)
                    (TorchServe/           (pre/post processing)
                     Triton/MLflow)
                              │
                              ▼
                    [MinIO S3 Storage]
                    (model artifacts)
```

### 5.2 Namespace Strategy

```yaml
# Namespace baru yang dibutuhkan
- kserve-system      # KServe controller, webhook
- model-serving      # InferenceService deployments
```

Label namespace `model-serving`:
```yaml
app.kubernetes.io/created-by: aide
cryptophys.io/domain: cerebrum
cryptophys.io/pool: apps-ha  # atau node pool khusus jika ada GPU
```

### 5.3 Resource Hierarchy

```
ClusterQueue (Kueue)
└── LocalQueue: model-serving-queue (di namespace model-serving)
    ├── InferenceService: llm-predictor (prioritas: cryptophys-ai-workload)
    └── InferenceService: classifier (prioritas: cryptophys-standard)
```

---

## 6. Rencana Implementasi

### Fase 1: Fondasi (Prerequisite)

- [ ] Konfirmasi ketersediaan GPU di node `nexus-tower` atau rencanakan pengadaan
- [ ] Tentukan model apa yang akan di-serve (menentukan runtime yang dibutuhkan)
- [ ] Setup MinIO bucket untuk model artifacts
- [ ] Audit Kyverno policies yang akan konflik dengan KServe

### Fase 2: Instalasi KServe

**Tahapan GitOps (setelah Stage 60-ray):**

```
clusters/cryptophys-genesis/kustomization/
├── 00-crds.yaml           # Tambahkan KServe CRDs
├── 62-kserve.yaml         # Flux Kustomization untuk KServe controller
└── 63-kserve-crs.yaml     # InferenceService pertama (baru)
```

**Direktori platform baru:**
```
platform/infrastructure/kserve/
├── kustomization.yaml
├── kserve-operator.yaml        # HelmRelease KServe
├── kserve-config.yaml          # ClusterServingRuntime definitions
├── kserve-netpol.yaml          # Network policies
└── policy-exception.yaml       # Kyverno exceptions
```

**Helm source yang perlu ditambahkan ke `05-sources.yaml`:**
```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: kserve-charts
  namespace: flux-system
spec:
  interval: 1h
  url: https://kserve.github.io/kserve
```

### Fase 3: Serving Runtime Pertama

Mulai dengan runtime yang paling sederhana:
1. **Scikit-learn / XGBoost** — tidak butuh GPU, cocok untuk proof of concept
2. **MLflow** — jika MLflow dipakai sebagai model registry
3. **Triton Inference Server** — untuk model PyTorch/ONNX dengan GPU

### Fase 4: Integrasi Lanjutan

- Pipeline Tekton untuk otomatisasi build serving image → push ke Harbor → update InferenceService
- Alerting Prometheus untuk latency tinggi / error rate inference
- Canary rollout via HTTPRoute traffic weights di Envoy Gateway

---

## 7. Perbandingan Alternatif

| Solusi | Kompleksitas | GPU Support | Scale-to-zero | Fit dengan Platform |
|---|---|---|---|---|
| **KServe (RawDeployment)** | Rendah-Sedang | Ya | Tidak | **Tinggi** |
| **KServe (Serverless)** | Tinggi | Ya | Ya | Rendah (butuh Knative) |
| **Ray Serve** | Rendah | Ya | Tidak | Tinggi (sudah ada) |
| **Seldon Core** | Sedang | Ya | Tidak | Sedang |
| **BentoML** | Rendah | Ya | Tidak | Sedang |
| **Triton Standalone** | Rendah | Ya | Tidak | Sedang (single runtime) |

**Kesimpulan perbandingan:**
- Jika kebutuhan utama adalah **standarisasi multi-framework** dan REST/gRPC inference endpoint yang mudah di-manage via GitOps → **KServe RawDeployment**
- Jika kebutuhan utama adalah **distributed inference dan pipeline ML** → **Ray Serve** (sudah ada)
- Jika hanya satu framework (misal PyTorch) → pertimbangkan **Triton standalone**

---

## 8. Keputusan yang Perlu Dibuat

Sebelum implementasi dimulai, tim perlu menjawab pertanyaan berikut:

1. **GPU availability**: Apakah node `nexus-tower` memiliki GPU? Tipe apa?
2. **Model target**: Framework apa yang akan di-serve? (PyTorch, TensorFlow, Scikit-learn, LLM?)
3. **Scale-to-zero**: Apakah diperlukan? (Jika ya, perlu evaluasi Knative)
4. **KServe vs Ray Serve**: Apakah keduanya akan dipakai? Apa pembagian fungsinya?
5. **Model registry**: Apakah MLflow atau registry terpisah perlu ditambahkan?
6. **Namespace**: Serving di `cqls-compute` (bersama Ray) atau namespace baru `model-serving`?
7. **Autoscaling target**: HPA berbasis CPU/memory atau custom metrics (KEDA)?

---

## 9. Risiko Keseluruhan

| Risiko | Dampak | Probabilitas | Prioritas |
|---|---|---|---|
| Tidak ada GPU untuk LLM | Tinggi | Sedang | **Kritis** |
| Kyverno policy conflict | Sedang | Tinggi | **Tinggi** |
| Ray vs KServe overlap | Sedang | Sedang | Sedang |
| Resource contention | Sedang | Rendah | Rendah |
| Tidak ada model registry | Rendah | Tinggi | Rendah |

---

## 10. Rekomendasi Final

**KServe layak diimplementasikan di cryptophys** dengan kondisi:

1. **Gunakan RawDeployment mode** — hindari Knative untuk menjaga kesederhanaan platform
2. **Prioritaskan konfirmasi GPU** — tanpa GPU, manfaat KServe untuk use case LLM terbatas
3. **Mulai dari cryptophys-genesis** — gunakan development cluster sebagai sandbox sebelum ke talos-prod
4. **Buat Kyverno policy exception** terlebih dahulu sebelum install KServe controller
5. **Tetapkan pembagian tugas** antara Ray (training/batch) dan KServe (online serving)
6. **Gunakan MinIO yang sudah ada** sebagai model storage backend — tidak perlu komponen tambahan

**Timeline yang disarankan:**
- Fase 1 (Prerequisite & Keputusan): 1 minggu
- Fase 2 (Install KServe di genesis): 1 minggu
- Fase 3 (Runtime pertama + validasi): 2 minggu
- Fase 4 (Integrasi penuh + talos-prod): 2-4 minggu

---

*Dokumen ini dibuat sebagai asesmen awal. Review diperlukan dari tim ML/AI, platform engineering, dan security sebelum implementasi.*
