const { adminSupabase } = require("../../all_imports");

async function getPartnerId(userId) {
    const { data, error } = await adminSupabase.rpc('get_accepted_partner', {
        target_user_id: userId
    });

    if (error || !data || data.length === 0) return null;
    return data[0].id;
}

module.exports = { getPartnerId };
