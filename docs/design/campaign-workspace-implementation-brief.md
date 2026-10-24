# Campaign Workspace — chuẩn triển khai giao diện

## Nguồn tham chiếu

- Mockup chuẩn: `docs/design/marketingos-campaign-workspace-reference.png`
- Màn hình này là **Campaign Workspace**: trang làm việc hằng ngày của đội marketing, không phải landing page hay dashboard chỉ để xem số liệu.

## Mục tiêu UX

Người dùng phải mở được một campaign và, trong một màn hình, biết ngay:

1. Campaign đang ở giai đoạn nào, bao nhiêu phần trăm hoàn tất và việc nào đang chặn tiến độ.
2. Kịch bản/tài liệu nào đang chờ góp ý hoặc duyệt, ai là người phụ trách và phản hồi mới nhất là gì.
3. Cuộc họp, hạn chót và thông báo cần làm tiếp theo.
4. Đề xuất tiếp theo của AI, nhưng không tự gửi email, đăng bài hoặc gọi dịch vụ bên ngoài.

## Bố cục desktop (>= 1280px)

```
┌──────────────────┬───────────────────────────────────────────────────────┐
│ Sidebar 240px    │ Top bar: search · notifications · profile              │
│                  ├───────────────────────────────────────────────────────┤
│ MarketingOS      │ Campaign header: breadcrumb, title, client, dates,     │
│ Overview         │ progress 72%, status, “Mời người duyệt”               │
│ Campaigns        ├───────────────────────────────────────────────────────┤
│ Content Studio   │ Lifecycle rail: Brief → Strategy → Content → Review → │
│ Calendar         │ Launch                                                 │
│ Clients          ├──────────────────────────────┬────────────────────────┤
│ Templates        │ Cột chính (2/3):             │ Cột phụ (1/3):          │
│ Settings         │ - Việc ưu tiên               │ - AI Campaign Copilot   │
│                  │ - Hàng chờ duyệt             │ - Cuộc họp sắp tới      │
│                  │ - Feedback mới               │ - Sức khoẻ campaign     │
└──────────────────┴──────────────────────────────┴────────────────────────┘
```

## Các component bắt buộc

### CampaignHeader

- Breadcrumb `Campaigns / [tên campaign]`; tên campaign, khách hàng, owner, thời gian, trạng thái.
- Thanh tiến độ có số phần trăm thật, tính từ milestone/task chứ không hard-code.
- Nút chính `Mời người duyệt`: mở dialog có email, vai trò, campaign scope, hạn invite và preview email. Người dùng phải tự bấm xác nhận gửi.
- Badge `AI assisted` khi có nội dung do AI tạo hoặc chỉnh sửa từ AI.

### CampaignLifecycle

- Các bước: `Brief`, `Strategy`, `Content & Scripts`, `Review`, `Launch`, `Report`.
- Mỗi bước có một trạng thái rõ: `not_started`, `in_progress`, `blocked`, `ready_for_review`, `completed`.
- Click vào bước mở đúng tab/route dữ liệu, không chỉ đổi màu giao diện.

### PriorityTaskList

- Mỗi dòng: trạng thái, tiêu đề, người được giao, deadline, priority, liên kết artifact/milestone.
- Có thể lọc `Của tôi`, `Quá hạn`, `Đang chờ phản hồi`; không làm drag-drop giả nếu backend chưa lưu thứ tự/trạng thái.
- Task bị block phải hiển thị lý do/blocker.

### ApprovalQueue

- Card của một bản kịch bản: thumbnail/loại, phiên bản, người yêu cầu, người cần duyệt, deadline, phản hồi mới nhất.
- CTA `Mở để duyệt` dẫn tới trang review có nội dung, version history, comment theo đoạn và quyết định rõ ràng `Approve`, `Request changes`, `Reject`.
- Chỉ người được chỉ định mới nhìn thấy các quyết định của họ; mỗi approver chỉ quyết định một lần trên cùng phiên bản, trừ khi mở vòng duyệt mới.

### AICopilot

- Hiển thị một “next best action” có căn cứ từ dữ liệu campaign; kèm CTA như `Tạo brief`, `Phân tích survey`, `Lên outline`, `Tạo bản dịch`, `Tạo image prompt`.
- Trước khi gửi dữ liệu khách hàng ra AI provider: hiển thị provider, dữ liệu sẽ gửi, mục đích, và yêu cầu consent của workspace owner/admin.
- Mọi output lưu AI run, model/provider, prompt version, nguồn đầu vào, thời điểm, người kích hoạt và trạng thái human review.

### Meetings & Campaign health

- Meeting hiển thị thời gian theo timezone của workspace, người tham gia, RSVP, link họp và reminder đã lên lịch.
- Campaign health gồm timeline, workload, review risk, budget (nếu có); từng chỉ số phải dẫn về dữ liệu nguồn.

## Responsive

- 1024px trở xuống: sidebar collapse; cột phụ xuống dưới cột chính.
- 768px trở xuống: campaign header xếp dọc; lifecycle cuộn ngang; actions vào menu; mỗi task/approval thành card đủ lớn để thao tác cảm ứng.
- Không được che thao tác duyệt, deadline hoặc trạng thái vì responsive.

## Design tokens

```css
:root {
  --navy-950: #101B75;
  --indigo-700: #3730D4;
  --teal-600: #0FAD9A;
  --amber-500: #F59E0B;
  --rose-600: #E5484D;
  --surface: #F8F9FC;
  --card: #FFFFFF;
  --ink: #172033;
  --muted: #68738D;
  --line: #E6E9F2;
  --radius-card: 16px;
  --shadow-card: 0 8px 24px rgba(23, 32, 51, .08);
}
```

- Dùng font sans hiện có trong Rails hoặc Inter; chữ nội dung tối thiểu 14px, tiêu đề card 16px, tiêu đề campaign 28–32px.
- Card trắng trên nền off-white, border mảnh, khoảng cách theo thang 4/8/12/16/24/32.
- Không dùng emoji thay icon nghiệp vụ; dùng một bộ SVG icons nhất quán, accessible label cho icon-only button.
- Không dùng Tailwind CDN trong production. Thiết lập CSS/Tailwind build cục bộ hoặc CSS variables có version control.

## Thứ tự bắt buộc trước khi styling

1. Sửa authorization để một request bị từ chối dừng hẳn trước mọi read/write/export; thêm request specs cho direct URL/POST của từng role.
2. Cô lập tenant ở mọi foreign key: client, campaign, artifact, assignee, collaborator, comment, approval và event phải thuộc đúng organization/campaign.
3. Thiết kế migration/model thật cho approval rounds, reviewer invitation, task milestone/reminder, meeting attendee/RSVP, script type/version/comment thread, template/prompt library và audit log.
4. Sau đó mới thay Dashboard và Campaign Show bằng các component ở trên, dùng dữ liệu thật và empty/loading/error states.
5. Tích hợp AI, email, lịch, dịch và image qua server-side adapters; mặc định mock/disabled trong local nếu chưa có key hợp lệ. Không nhúng Coding Plan/ZCode key vào web app.

## Prompt bàn giao cho ZCode

```text
Bạn là senior Rails product engineer. Đọc hai file:
1) E:/marketing-agentic-platform/docs/design/marketingos-campaign-workspace-reference.png
2) E:/marketing-agentic-platform/docs/design/campaign-workspace-implementation-brief.md

Hãy dùng mockup là chuẩn visual và brief là chuẩn hành vi. Đừng chỉ đổi CSS: đây phải là Campaign Workspace hoạt động bằng dữ liệu thật.

Trước khi làm UI, sửa toàn bộ P0 về RBAC/tenant isolation. Một redirect bị từ chối quyền phải chấm dứt action; mọi client_id, artifact_id, assignee_id, collaborator và approval phải được scope theo organization/campaign. Viết request specs chứng minh request trực tiếp của role client/viewer không đọc/ghi được dữ liệu ngoài scope.

Sau đó thực hiện theo từng PR/commit nhỏ:
1. Tạo data model và migrations cho lifecycle/milestone, approval rounds + assigned reviewers, reviewer invite, artifact comments, template/prompt library, task/reminder, meeting attendees.
2. Xây layout desktop/mobile y hệt hierarchy trong reference: sidebar, topbar, campaign header, lifecycle rail, Priority Tasks, Approval Queue, AI Copilot, Meetings, Campaign Health.
3. Thay số liệu hard-code bằng query/service thật; có loading, empty, error states; hiển thị thời gian theo timezone workspace.
4. Xây trang review kịch bản với version, comment thread, assigned approvers và state transition hợp lệ.
5. Đặt AI/email/calendar/translation/image sau provider adapters phía server. Local chỉ mock/log khi chưa có credentials; external email/AI action luôn cần preview + human confirmation/consent. Không đưa ZCode/Coding Plan key vào mã nguồn, git hay app runtime.

Không dùng Tailwind CDN cho production. Dùng CSS design tokens từ brief. Sau mỗi bước, chạy migration và test tương ứng; không phá demo seed. Báo cáo file đã sửa, migration mới, test đã chạy, và screenshot desktop + mobile trước khi kết thúc.
```

## Definition of done

- Owner, manager, editor, approver, viewer và client thấy đúng phạm vi dữ liệu; direct request bị chặn bằng test.
- Một campaign mẫu có task, deadline/reminder, artifact version, feedback theo artifact, approval round và meeting thật trong UI.
- Người được mời có thể xem/duyệt đúng campaign qua luồng invite an toàn, không xem CRM hay campaign khác.
- UI dùng được ở desktop và mobile; screenshot khớp hierarchy mockup, không chỉ một dashboard rỗng.
- Không thực gửi mail, gọi AI, dịch hay gen ảnh nếu provider/consent chưa được cấu hình.
