# Prompt UI chuyên biệt cho ZCode

> Dán nguyên khối bên dưới vào ZCode. Prompt này dành riêng cho việc thay UI Rails hiện tại theo mockup, không phải tiếp tục tạo dashboard CRUD chung chung.

```text
Hãy làm ngay phần UI/UX cho project Rails tại E:\marketing-agentic-platform.

Nguồn thiết kế BẮT BUỘC phải bám theo, không chỉ dùng để lấy cảm hứng:

E:\marketing-agentic-platform\docs\design\marketingos-campaign-workspace-reference.png

Nguồn quy tắc hành vi/component:

E:\marketing-agentic-platform\docs\design\campaign-workspace-implementation-brief.md

MỤC TIÊU

Thay giao diện CRUD hiện tại bằng một B2B SaaS Campaign Workspace đẹp, rõ luồng công việc và nhìn gần với mockup ở kích thước desktop 1536px. Đây là màn hình làm việc chính của marketing team: biết campaign đang ở đâu, việc nào gấp, kịch bản nào chờ duyệt, ai góp ý, lịch họp gì và AI đề xuất bước tiếp theo. Không dựng landing page. Không dựng dashboard KPI vô nghĩa.

KHÔNG ĐƯỢC LÀM

- Không trả lời bằng kế hoạch hay mô tả. Hãy sửa code thật, chạy app và tự kiểm tra giao diện.
- Không giữ giao diện hiện tại chỉ rồi thay vài màu/card.
- Không dùng Bootstrap/generic admin template, gradient loè loẹt, emoji làm icon, bảng toàn màn hình hoặc metric hard-code.
- Không tạo dữ liệu giả trong view. Dùng query/model hiện có; nếu dữ liệu cần thiết chưa có, thêm seed/fallback có chủ đích.
- Không phá RBAC hoặc mở rộng quyền client/guest; các CTA phải ẩn/disabled theo quyền thật.
- Không gọi AI/email/image/calendar provider bên ngoài chỉ để làm giao diện.

PHẠM VI FILE UI ƯU TIÊN

1. `app/views/layouts/application.html.erb`
2. `app/views/dashboard/index.html.erb`
3. `app/views/campaigns/show.html.erb`
4. partials/components mới dưới `app/views/shared/` hoặc ViewComponent nếu project đã có setup phù hợp
5. stylesheet/build pipeline cục bộ; không dùng Tailwind CDN cho production
6. helpers/query objects tối thiểu để view không chứa business logic phức tạp
7. seed và system/request specs cần thiết để demo đẹp bằng dữ liệu thật

VISUAL SYSTEM BẮT BUỘC

- Nền app: `#F8F9FC`; card: trắng; chữ chính `#172033`; chữ phụ `#68738D`; viền `#E6E9F2`.
- Sidebar deep navy `#101B75`, rộng khoảng 248px desktop; branding `MarketingOS`; workspace/user ở chân sidebar.
- Primary indigo `#3730D4`; success teal `#0FAD9A`; warning amber `#F59E0B`; danger `#E5484D`.
- Card bo 16px, bóng nhẹ; spacing 4/8/12/16/24/32; heading campaign 28–32px; body không nhỏ hơn 14px.
- Icon bằng inline SVG/accessibility label hoặc một icon set hiện có trong project. Màu trạng thái luôn có text, không chỉ dựa vào màu.
- Font sans sạch, nhất quán. Đừng dùng các class Tailwind mà chỉ chạy nhờ `<script src="https://cdn.tailwindcss.com">`.

APP SHELL — PHẢI GIỐNG HIERARCHY CỦA MOCKUP

- Sidebar cố định: Overview, Campaigns, Content Studio, Calendar, Clients, Templates, Settings.
- Topbar: search affordance, notifications, profile/avatar; không chiếm chiều cao dư thừa.
- Trạng thái active nav rõ bằng nền indigo sáng/viền hoặc pill.
- Với `client` role, chỉ hiện menu và phạm vi hợp lệ; không cho truy cập toàn bộ Clients/Templates/Settings.
- <=1024px: sidebar collapse thành drawer; <=768px: main content một cột, topbar và campaign header không tràn.

CAMPAIGN WORKSPACE — ĐÂY LÀ MÀN HÌNH ƯU TIÊN

Hãy thay campaign show bằng bố cục desktop sau:

1. Campaign Header
   - breadcrumb `Campaigns / [Tên campaign]`
   - tên lớn, logo/avatar khách hàng, client name, owner, khoảng ngày, status pill
   - progress thật từ task/milestone; nhãn ví dụ `72% complete`
   - CTA primary `Mời người duyệt`; CTA secondary rõ ràng như `Tạo nội dung`/`Xem brief`, có permission gate.

2. Lifecycle rail ngay dưới header
   - `Brief → Strategy → Content & Scripts → Review → Launch → Report`
   - mỗi bước có state text/icon: complete, in progress, blocked, not started
   - step hiện tại nổi bật; các step là link/tab tới phần dữ liệu tương ứng, không phải decoration.

3. Grid bên dưới: main 2 phần / right rail 1 phần
   - Main card 1: `Việc ưu tiên` — task rows gồm checkbox/status, title, owner avatar/initial, deadline, priority và trạng thái blocked/overdue. Có empty state tử tế.
   - Main card 2: `Đang chờ duyệt` — artifact/script card gồm loại, title, version, preview ngắn, reviewers, deadline, comment mới nhất và CTA `Mở để duyệt`.
   - Main card 3 (khi có data): `Góp ý mới` — feedback theo artifact/version; không chỉ campaign comment chung chung.
   - Right card 1: `AI Campaign Copilot` — one next-best action có lý do và CTA; trạng thái AI-assisted rõ ràng. CTA chỉ mở flow local/preview khi provider chưa cấu hình.
   - Right card 2: `Cuộc họp sắp tới` — datetime timezone, participant chips, agenda/link/RSVP nếu có; empty state nếu chưa có.
   - Right card 3: `Sức khoẻ campaign` — timeline, workload, review risk/budget nếu có. Số phải có nguồn dữ liệu, không hard-code.

DASHBOARD OVERVIEW

- Không phải lặp lại Campaign Workspace. Tạo landing dashboard có các section: `Việc của tôi`, `Chờ bạn duyệt`, `Campaign cần chú ý`, `Lịch tuần này`, `Hoạt động gần đây`.
- Cùng design system/sidebar/topbar; mọi card link đến campaign/artifact/task thật.
- Tính count bằng query tổng, không dùng collection đã `.limit` rồi gọi `.size` để hiển thị KPI tổng.

TRANG REVIEW KỊCH BẢN / ARTIFACT

- Có title/type/version/status; nội dung dễ đọc; version history; feedback/comment thread; reviewer/approval status; CTA gửi duyệt/approve/request changes/reject đúng quyền.
- Không đặt tất cả control vào một card hẹp. Nội dung chiếm main column, activity/approval ở right rail.
- Giữ dữ liệu version/comment hiện có, nhưng trình bày thành workflow chuyên nghiệp.

CHẤT LƯỢNG TRIỂN KHAI

- Tách partial/component tái sử dụng: app shell, nav item, status pill, campaign header, lifecycle rail, task row, approval card, empty state, avatar stack.
- Semantic HTML, focus states, aria-label icon buttons, contrast tốt; không gây horizontal scroll ở 320px.
- Có loading/empty/error state; ảnh/profile fallback bằng initials/SVG nếu không có asset.
- Giữ login/demo route hiện có. Không đổi password demo hoặc xoá seeds.

QUY TRÌNH BẮT BUỘC

1. Đọc mockup PNG ở trên trước khi code.
2. Kiểm tra dữ liệu/models/routes hiện tại và map component vào dữ liệu thật.
3. Implement app shell + Campaign Workspace trước; sau đó Dashboard/Artifact review.
4. Seed đủ một campaign demo có task, artifact, approval/comment và event để mọi card có nội dung khi owner đăng nhập.
5. Khởi động app bằng `./start.ps1` hoặc PowerShell tương thích, mở `http://localhost:3000`, đăng nhập `owner@demo.vn / password123`.
6. Tự chụp/kiểm tra screenshot desktop (1536px) và mobile (390px), sửa đến khi hierarchy, tỷ lệ, màu, spacing gần mockup rõ rệt.
7. Chạy test liên quan. Báo cáo cụ thể: file đã sửa, dữ liệu thật được map ở đâu, route/screenshots đã kiểm tra.

TIÊU CHÍ NGHIỆM THU

- Nhìn vào `Campaign Workspace` phải thấy ngay sidebar navy, topbar, campaign header/progress, lifecycle rail, task priority, approval queue, AI copilot, meeting và campaign health — cùng hierarchy với mockup.
- Không còn cảm giác “Rails scaffold / form CRUD”.
- Dùng được với dữ liệu demo, responsive và không làm hỏng phân quyền hiện có.
- Khi hoàn thành, đừng chỉ nói đã làm: đưa danh sách file, lệnh test, screenshot paths và những chỗ chưa thể kết nối vì thiếu credentials.
```
