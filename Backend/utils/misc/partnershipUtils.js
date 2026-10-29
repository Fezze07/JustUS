const { adminSupabase, assertDbSuccess } = require("../../all_imports");

async function getPartnerId(userId) {
    const { data, error } = await adminSupabase.rpc('partnership_get_accepted_partner', {
        target_user_id: userId
    });

    if (error || !data || data.length === 0) return null;
    return data[0].id;
}

async function getCancellationPartnerId(userId) {
    const { data, error } = await adminSupabase.rpc('partnership_get_cancellation_partner', {
        p_user_id: userId
    });

    if (error || data == null) return null;
    if (typeof data === 'number') return data;
    if (Array.isArray(data)) {
        if (data.length === 0) return null;
        const first = data[0];
        if (typeof first === 'number') return first;
        if (first && typeof first === 'object') {
            return first.partner_id ?? first.id ?? Object.values(first)[0] ?? null;
        }
        return null;
    }
    if (typeof data === 'object') {
        return data.partner_id ?? data.id ?? Object.values(data)[0] ?? null;
    }
    return null;
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

// Mirrors partnership_is_member(); the service-role client has no auth.uid().
async function isPartnershipMember(partnershipId, userId) {
    const row = assertDbSuccess(
        await adminSupabase
            .from('partnerships')
            .select('id')
            .eq('id', partnershipId)
            .eq('status', 'accepted')
            .or(`user_id_1.eq.${userId},user_id_2.eq.${userId}`)
            .maybeSingle(),
        'DB_READ_001'
    );
    return row != null;
}

module.exports = { getPartnerId, getCancellationPartnerId, getPartnershipId, isPartnershipMember };
