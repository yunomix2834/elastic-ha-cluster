Rồi, giờ mình sẽ “đóng hộp” phần quan trọng nhất của HA: **khi server chết thì dữ liệu ra sao** và **quy trình bầu master theo quorum** (kiểu bạn có 3 master-eligible + 3 data như sơ đồ).

Mình sẽ bám sát đúng các thuật ngữ bạn đã viết, và thêm những khái niệm **bắt buộc phải biết** khi nói về HA (cluster health, promote replica, shard relocation, split-brain, network partition, cluster-state publish).

---

## A. Khi server chết thì dữ liệu như nào?

Để nói cực kỳ rõ, ta giả lập một index:

* `number_of_shards = 3` → primary shards: `P0, P1, P2`
* `number_of_replicas = 1` → replica shards: `R0, R1, R2`
* 3 data nodes: `data-1`, `data-2`, `data-3`

### A1) Cách ES “rải” shard lên data nodes (trạng thái bình thường)

Một phân bổ thường gặp (minh hoạ) sẽ là:

* `data-1`: `P0`, `R1`
* `data-2`: `P1`, `R2`
* `data-3`: `P2`, `R0`

**Luật cứng:** `R0` không bao giờ được nằm cùng node với `P0` (trừ trường hợp cluster không đủ node và bạn ép, nhưng mặc định ES sẽ tránh).

### A2) Cluster health: GREEN / YELLOW / RED là gì?

* **GREEN**: tất cả primary *và* replica đều “STARTED” → đủ HA.
* **YELLOW**: tất cả primary đều “STARTED” nhưng *thiếu replica* → vẫn chạy, nhưng mất một phần HA.
* **RED**: có primary shard bị mất → index thiếu dữ liệu/không phục vụ đầy đủ.

---

## B. Trường hợp 1: 1 **data node chết** (hay gặp nhất)

Giả sử `data-2` chết (mất cả ổ đĩa hoặc container/VM down).

### B1) Ngay khoảnh khắc node chết

ES phát hiện node rớt qua cơ chế **failure detection** (các node ping/handshake). Khi xác nhận node “gone”:

* Mất `P1` (primary shard của shard 1)
* Mất `R2` (replica của shard 2) (tuỳ phân bổ)

Cluster lúc này có thể thoáng qua **RED/YELLOW**, nhưng ES sẽ cố hồi ngay nếu còn replica.

### B2) Promote replica thành primary (cơ chế cứu cụm)

Shard 1 có:

* `P1` mất vì nằm ở `data-2`
* nhưng `R1` đang nằm ở `data-1` (theo ví dụ)

ES sẽ làm bước cực quan trọng:

✅ **Promote `R1` → thành primary mới của shard 1**

Tức là:

* `R1` *đổi vai* thành “primary”
* cluster tránh được trạng thái RED kéo dài

Kết quả:

* Các primary (`P0`, `P1(new)`, `P2`) vẫn đủ để phục vụ search/indexing.
* Nhưng replica bị thiếu (vì có một số replica nằm trên node chết) → cluster thường chuyển **YELLOW**.

### B3) Rebuild replica để quay lại GREEN

Sau khi promote, ES sẽ tìm nơi để tạo replica mới (nếu còn node đủ tài nguyên):

* Ví dụ: tạo lại replica cho shard 1 ở `data-3` chẳng hạn.

Đây là quá trình **recovery**:

* Có thể copy dữ liệu từ primary → replica qua network.
* Tốn I/O, CPU, network.

Khi rebuild xong hết replica → cluster về **GREEN**.

### B4) Ghi dữ liệu (indexing) trong lúc đang YELLOW có sao không?

Có 2 ý:

1. **Vẫn ghi được** nếu primary shard vẫn còn.
2. Mức “an toàn” phụ thuộc setting `wait_for_active_shards`:

   * Nếu bạn yêu cầu chờ replica (ví dụ “1 replica phải active”) thì khi thiếu replica, indexing có thể bị chặn hoặc trả lỗi/timeout.
   * Nếu không yêu cầu, ES sẽ nhận ghi và replicate “khi có thể”.

**Ý nghĩa HA:**
Replica không chỉ để đọc nhanh mà là “dây an toàn” khi data node chết.

---

## C. Trường hợp 2: 1 **master-eligible node chết** (não cụm bị thương)

Bạn có 3 master-eligible nodes (master-1, master-2, master-3) → đây là chuẩn HA.

### C1) Mất 1 master có sao không?

Thông thường: **không sao lớn**, cluster vẫn hoạt động vì còn quorum (2/3).

* Cụm vẫn có master (hoặc bầu lại nhanh).
* Dữ liệu trên data nodes không mất (master tách role, không giữ data).
* Điều bị ảnh hưởng chủ yếu là: các thay đổi cluster-state (allocation, create index, mapping update…) có thể chậm một nhịp trong thời gian bầu lại.

### C2) Nếu master hiện tại chết thì sao?

Nếu con đang giữ vai trò **master hiện tại** chết:

* Cluster sẽ bầu master mới (quorum vẫn đủ vì còn 2 master-eligible nodes).
* Quá trình này thường rất nhanh (vài giây tuỳ môi trường).

Trong thời gian “no master” ngắn:

* Nhiều request quản trị (create index, update settings) có thể fail tạm.
* Search thường vẫn chạy một phần, nhưng indexing/metadata operations có thể bị gián đoạn.

---

## D. Trường hợp 3: chết **2/3 master-eligible** (mất quorum → cluster “mất não”)

Đây là chỗ quorum “lộ mặt”.

Nếu chỉ còn 1 master-eligible node sống:

* Quorum của 3 là **2**
* 1 node **không đủ quorum** → không thể elect master

Hậu quả:

* Cluster rơi vào trạng thái **NO MASTER**
* Không có ai “chốt” cluster state mới
* Các hoạt động quan trọng sẽ bị chặn (đặc biệt là các thao tác cần cluster-state update)

⚠️ Dữ liệu trên disk data nodes có thể vẫn còn, nhưng cluster không điều phối được → không phục vụ đúng nghĩa.

**Đây là lý do 3 master-eligible là cấu hình kinh điển.**

---

## E. Trường hợp 4: network partition (split-brain) — thứ giết cluster âm thầm

Giả sử mạng bị chia thành 2 phe:

* Phe A: master-1 + data-1
* Phe B: master-2 + master-3 + data-2 + data-3

Quorum = 2/3, vậy:

* Phe B có 2 master-eligible → **đủ quorum** → tiếp tục là cluster hợp lệ
* Phe A chỉ có 1 master-eligible → **không đủ quorum** → phe A **không được phép tự xưng master**

Điểm hay:
✅ Cơ chế quorum giúp **ngăn split-brain** (2 cluster cùng ghi dữ liệu diverge).

Phe A sẽ “đóng băng” phần quản trị, tránh ghi dữ liệu tạo lịch sử song song.

---

## F. Dữ liệu có “mất” thật không? Phân biệt 3 loại mất

Khi bạn nói “mất dữ liệu”, phải phân biệt:

### F1) Mất node nhưng còn replica → **không mất dữ liệu**

* Replica promote lên primary
* Dữ liệu còn đủ (logical data intact)

### F2) Mất node và shard đó **không có replica** → **có thể mất**

* Nếu shard primary chết và không có replica nào đang live → shard đó đỏ (RED)
* Index thiếu dữ liệu cho shard đó → truy vấn sai/thiếu, ghi có thể fail

### F3) “Mất data thật sự” (disk corruption / xóa volume / snapshot không có)

* Lúc này dù cluster có bầu master được, shard vẫn không thể phục hồi nếu không có replica/snapshot.
* HA chuẩn ngoài replica còn cần **snapshot** (S3/NFS/…).

---

# G. Quy trình bầu master node theo quorum (cực kỳ chi tiết nhưng vẫn đọc được)

Elasticsearch hiện đại (từ 7.x trở lên) dùng cơ chế “cluster coordination” (thường gọi nôm na là **Zen2**). Ý tưởng giống Raft ở mức “quy trình quorum”, nhưng ES là ES: nó tối ưu cho cluster-state.

Bạn cần hiểu 4 khái niệm:

1. **Master-eligible nodes**: các node được phép tham gia bầu master
2. **Voting configuration**: tập các node đang có quyền biểu quyết (thường chính là master-eligible đang tham gia cluster)
3. **Quorum (majority)**: đa số của voting configuration
4. **Cluster state publication**: master không chỉ được bầu; mọi thay đổi cluster-state phải được “commit” qua quorum

---

## G1) Khi nào cần bầu master?

* Cluster start lần đầu (bootstrap)
* Master hiện tại chết
* Network partition làm mất liên lạc với master

## G2) Voting configuration và quorum tính như nào?

Nếu voting configuration có N node:

* quorum = `floor(N/2) + 1`

Ví dụ:

* N=3 → quorum=2
* N=5 → quorum=3

Trong stack bạn: 3 master-eligible → quorum = 2.

## G3) Bầu master diễn ra theo “đời sống” như nào?

Mình mô tả theo bước logic (không cần thuộc thuật ngữ nội bộ):

### Bước 1 — Phát hiện không có master

Các master-eligible nodes nhận ra “không còn master hợp lệ” (timeout / disconnect).

### Bước 2 — Bắt đầu election (ứng viên đề cử)

Một node sẽ “ứng cử” làm master và **xin phiếu** từ các node voting khác.

### Bước 3 — Xin phiếu + đạt quorum

* Nếu ứng viên nhận được **>= quorum** phiếu → thắng cử → trở thành master mới.
* Nếu không ai đạt quorum (mạng chia nhỏ, node chết quá nhiều) → không có master.

### Bước 4 — Master mới “publish” cluster state

Master mới sẽ:

* nắm cluster state hiện tại (hoặc state mới nhất nó biết)
* **publish** cluster state cho các node khác
* các node khác **ack** (xác nhận) — và điểm quan trọng:

✅ Cluster state chỉ được coi là “commit” khi master nhận ack từ **quorum** nodes.

Đây là lý do cluster không bị “hai phe commit hai state khác nhau”.

---

## G4) Kịch bản cụ thể: master-2 đang là master, master-2 chết

* master-1, master-3 phát hiện mất master.
* Cả hai có thể cùng ứng cử (race condition).
* Ví dụ master-1 xin phiếu:

  * master-1 vote cho chính nó
  * master-3 vote cho master-1
  * đạt 2/3 → master-1 thắng
* master-1 publish cluster state → cluster tiếp tục

Trong thời gian bầu (vài giây):

* thao tác quản trị/metadata có thể fail tạm
* sau đó hồi ngay

---

## G5) Vì sao “2 master” là cấu hình hay chết?

Nếu chỉ có 2 master-eligible:

* quorum = 2 (đa số của 2 là 2)
* chết 1 → còn 1 → **không đủ quorum** → cluster “mất não”

Nên cách tiết kiệm tài nguyên mà vẫn HA là:

* 2 master + 1 **voting-only node** (nếu bạn dùng kiểu đó)
  hoặc đơn giản nhất:
* 3 master-eligible như bạn đang làm.

---

# H. Chốt lại theo đúng sơ đồ của bạn

Với mô hình:

* 3 master-eligible
* 3 data nodes (có replica)
* 1-2 coordinating nodes

Thì:

✅ Chết 1 data node: **không mất dữ liệu** (nếu replica=1 và được phân bổ đúng), cluster thường YELLOW tạm rồi về GREEN.
✅ Chết 1 master: **cluster vẫn sống** vì quorum còn đủ.
❌ Chết 2 master: **cluster mất master** (no quorum) → gián đoạn nặng.
✅ Network split: phe không đủ quorum sẽ “đóng băng” → tránh split-brain.

---

Nếu bạn muốn “phần nghiên cứu” của bạn đọc cực thuyết phục, bước tiếp theo là mình viết **một flow theo timeline** (T0 node chết, T1 detect, T2 promote, T3 rebalance, T4 green) + kèm “cluster health đổi màu” theo từng bước. Văn đó rất hợp để đưa thẳng vào report.
