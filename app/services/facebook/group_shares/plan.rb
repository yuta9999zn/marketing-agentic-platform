# frozen_string_literal: true

module Facebook
  module GroupShares
    # Lên kế hoạch chia sẻ một bài Page ĐÃ ĐĂNG vào nhiều nhóm.
    #
    # - Mỗi nhóm một lượt chia sẻ, giờ hẹn giãn cách đều (mặc định 30 phút):
    #   đăng dồn cùng lúc vào nhiều nhóm dễ bị Facebook coi là spam.
    # - Nhóm đã có trong kế hoạch của bài này thì bỏ qua (không tạo trùng).
    # - Người phụ trách: chọn trong form, không thì người phụ trách mặc định của
    #   nhóm, không nữa thì người lên kế hoạch.
    class Plan
      SPACING_OPTIONS = [ 10, 15, 20, 30, 45, 60, 90, 120 ].freeze
      DEFAULT_SPACING = 30

      Result = Struct.new(:created, :skipped_existing, keyword_init: true)

      def self.call(**kwargs) = new(**kwargs).call

      def initialize(post:, user:, group_ids:, start_at:, spacing_minutes: DEFAULT_SPACING, assignee_id: nil)
        @post = post
        @user = user
        @org = post.organization
        @group_ids = Array(group_ids).map(&:to_s).reject(&:blank?).uniq
        @start_at = start_at
        @spacing = spacing_minutes.to_i
        @assignee_id = assignee_id.presence
      end

      def call
        raise Facebook::StateError, I18n.t("marketingos.facebook_groups.errors.post_not_published") unless @post.published?
        raise ArgumentError, I18n.t("marketingos.facebook_groups.errors.no_groups") if @group_ids.empty?
        raise ArgumentError, I18n.t("marketingos.facebook_groups.errors.bad_spacing") unless SPACING_OPTIONS.include?(@spacing)

        start = parse_start
        groups = @org.facebook_groups.active.where(id: @group_ids).index_by { |g| g.id.to_s }
        raise ArgumentError, I18n.t("marketingos.facebook_groups.errors.no_groups") if groups.empty?

        forced_assignee = resolve_assignee(@assignee_id) if @assignee_id
        existing = @post.facebook_group_shares.pluck(:facebook_group_id).to_set
        created = []
        skipped = []

        FacebookGroupShare.transaction do
          @group_ids.filter_map { |id| groups[id] }.each do |group|
            if existing.include?(group.id)
              skipped << group
              next
            end
            created << FacebookGroupShare.create!(
              organization: @org, facebook_post: @post, facebook_group: group, created_by: @user,
              assignee: forced_assignee || group.default_assignee || @user,
              scheduled_at: start + (created.size * @spacing).minutes
            )
          end
        end

        created.each { |share| Reminders.schedule(share) }
        if created.any?
          AuditLog.record!(org: @org, user: @user, action: "facebook.group_share.planned", subject: @post,
                           details: { "group_ids" => created.map(&:facebook_group_id), "spacing_minutes" => @spacing,
                                      "start_at" => start.utc.iso8601 })
        end
        Result.new(created: created, skipped_existing: skipped)
      end

      private

      # Giờ bắt đầu theo múi giờ của bài; để trống → 5 phút nữa. Không nhận giờ quá khứ.
      def parse_start
        return 5.minutes.from_now.change(sec: 0) if @start_at.blank?

        at = Facebook::Posts::Scheduling.parse_local(@start_at, @post.timezone)
        raise ArgumentError, I18n.t("marketingos.facebook_groups.errors.start_in_past") if at < Time.current - 1.minute

        at
      end

      def resolve_assignee(id)
        user = FacebookGroupShare.assignable_users(@org).find_by(id: id)
        raise ArgumentError, I18n.t("marketingos.facebook_groups.errors.bad_assignee") if user.nil?

        user
      end
    end
  end
end
