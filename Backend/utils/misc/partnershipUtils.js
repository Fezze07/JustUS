const { adminSupabase } = require("../../all_imports");

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

module.exports = { getPartnerId, getCancellationPartnerId };
