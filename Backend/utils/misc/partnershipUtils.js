const { adminSupabase, assertDbSuccess } = require("../../all_imports");

async function getPartnerId(userId) {
    const { data, error } = await adminSupabase.rpc('partnership_get_accepted_partner', {
        target_user_id: userId
    });

    if (error || !data || data.length === 0) return null;
    return data[0].id;
}

function normalizePartnerId(data) {
    if (data == null) return null;
    if (typeof data === 'number') return data;
    const first = Array.isArray(data) ? data[0] : data;
    if (first == null) return null;
    if (typeof first === 'number') return first;
    if (typeof first === 'object') {
        return first.partner_id ?? first.id ?? Object.values(first)[0] ?? null;
    }
    return null;
}

async function getCancellationPartnerId(userId) {
    const { data, error } = await adminSupabase.rpc('partnership_get_cancellation_partner', {
        p_user_id: userId
    });

    if (error) return null;
    return normalizePartnerId(data);
}

async function getPartnershipId(userId) {
    for (const status of ['accepted', 'cancelled']) {
        const row = assertDbSuccess(
            await adminSupabase
                .from('partnerships')
                .select('id')
                .or(`user_id_1.eq.${userId},user_id_2.eq.${userId}`)
                .eq('status', status)
                .order('id', { ascending: false })
                .limit(1)
                .maybeSingle(),
            'DB_READ_001'
        );
        if (row) return row.id;
    }
    return null;
}

async function getPartnershipById(partnershipId) {
    const { data, error } = await adminSupabase
        .from('partnerships')
        .select('id, user_id_1, user_id_2, status, cancel_requested_by, cancel_expires_at')
        .eq('id', partnershipId)
        .maybeSingle();

    if (error || !data) return null;
    return data;
}

function isPartnershipParticipant(partnership, userId) {
    return partnership != null &&
        (partnership.user_id_1 === userId || partnership.user_id_2 === userId);
}

// Mirrors partnership_is_member(); the service-role client has no auth.uid().
async function isPartnershipMember(partnershipId, userId) {
    const row = assertDbSuccess(
        await adminSupabase
            .from('partnerships')
            .select('user_id_1, user_id_2')
            .eq('id', partnershipId)
            .eq('status', 'accepted')
            .maybeSingle(),
        'DB_READ_001'
    );
    return isPartnershipParticipant(row, userId);
}

module.exports = {
    getPartnerId,
    getCancellationPartnerId,
    getPartnershipId,
    getPartnershipById,
    isPartnershipParticipant,
    isPartnershipMember,
};
