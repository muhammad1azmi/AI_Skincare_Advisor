"""Skincare Product Catalog — curated product database with skin concern matching.

Products are tagged with skin concerns so notifications can be personalized
based on the user's skin profile (from AI analysis stored in session state).
"""

from typing import Optional

# Skin concern tags used for matching
CONCERN_ACNE = "acne"
CONCERN_DRY = "dry"
CONCERN_OILY = "oily"
CONCERN_AGING = "aging"
CONCERN_HYPERPIGMENTATION = "hyperpigmentation"
CONCERN_SENSITIVITY = "sensitivity"
CONCERN_PORES = "pores"
CONCERN_REDNESS = "redness"
CONCERN_DULL = "dullness"
CONCERN_SUN = "sun_protection"
CONCERN_ALL = "all"  # universal products

# Categories
CAT_CLEANSER = "Cleanser"
CAT_MOISTURIZER = "Moisturizer"
CAT_SUNSCREEN = "Sunscreen"
CAT_SERUM = "Serum"
CAT_EXFOLIANT = "Exfoliant"
CAT_MASK = "Mask"
CAT_TONER = "Toner"
CAT_EYE = "Eye Cream"
CAT_LIP = "Lip Care"
CAT_SPOT = "Spot Treatment"

# ─── Product Catalog ───
# Each product has: name, brand, category, description, original_price,
# discount_percent, concerns (list), and buy_url (e-commerce link).

PRODUCT_CATALOG = [
    # ── Cleansers ──
    {
        "name": "Hydrating Facial Cleanser",
        "brand": "CeraVe",
        "category": CAT_CLEANSER,
        "description": "Gentle, non-foaming cleanser with ceramides and hyaluronic acid. Perfect for daily use.",
        "original_price": 15.99,
        "discount_percent": 20,
        "concerns": [CONCERN_DRY, CONCERN_SENSITIVITY, CONCERN_ALL],
        "buy_url": "https://www.amazon.com/dp/B01MSSDEPK",
    },
    {
        "name": "SA Smoothing Cleanser",
        "brand": "CeraVe",
        "category": CAT_CLEANSER,
        "description": "Salicylic acid cleanser that exfoliates and smooths rough, bumpy skin.",
        "original_price": 14.99,
        "discount_percent": 15,
        "concerns": [CONCERN_ACNE, CONCERN_PORES, CONCERN_OILY],
        "buy_url": "https://www.amazon.com/dp/B09LRDKJJB",
    },
    {
        "name": "Toleriane Purifying Foaming Cleanser",
        "brand": "La Roche-Posay",
        "category": CAT_CLEANSER,
        "description": "Oil-free foaming cleanser with niacinamide for oily, sensitive skin.",
        "original_price": 17.99,
        "discount_percent": 25,
        "concerns": [CONCERN_OILY, CONCERN_ACNE, CONCERN_SENSITIVITY],
        "buy_url": "https://www.amazon.com/dp/B01N7T7JKJ",
    },

    # ── Moisturizers ──
    {
        "name": "Moisturizing Cream",
        "brand": "CeraVe",
        "category": CAT_MOISTURIZER,
        "description": "Rich moisturizer with 3 essential ceramides and MVE technology for 24-hour hydration.",
        "original_price": 19.99,
        "discount_percent": 25,
        "concerns": [CONCERN_DRY, CONCERN_SENSITIVITY, CONCERN_ALL],
        "buy_url": "https://www.amazon.com/dp/B00TTD9BRC",
    },
    {
        "name": "Cicaplast Baume B5+",
        "brand": "La Roche-Posay",
        "category": CAT_MOISTURIZER,
        "description": "Soothing multi-purpose balm for irritated, damaged skin with panthenol.",
        "original_price": 18.99,
        "discount_percent": 20,
        "concerns": [CONCERN_SENSITIVITY, CONCERN_REDNESS, CONCERN_DRY],
        "buy_url": "https://www.amazon.com/dp/B0060OUV5Y",
    },
    {
        "name": "Ultra Facial Cream",
        "brand": "Kiehl's",
        "category": CAT_MOISTURIZER,
        "description": "Lightweight, 24-hour daily moisturizer with squalane and glacial glycoprotein.",
        "original_price": 38.00,
        "discount_percent": 15,
        "concerns": [CONCERN_DRY, CONCERN_ALL],
        "buy_url": "https://www.amazon.com/dp/B003OCOQKW",
    },

    # ── Sunscreens ──
    {
        "name": "Anthelios Melt-In Sunscreen SPF 60",
        "brand": "La Roche-Posay",
        "category": CAT_SUNSCREEN,
        "description": "Lightweight, fast-absorbing broad-spectrum SPF 60 with Cell-Ox Shield technology.",
        "original_price": 35.99,
        "discount_percent": 20,
        "concerns": [CONCERN_SUN, CONCERN_AGING, CONCERN_HYPERPIGMENTATION, CONCERN_ALL],
        "buy_url": "https://www.amazon.com/dp/B002CML1VG",
    },
    {
        "name": "UV Aqua Rich Watery Essence SPF 50+",
        "brand": "Biore",
        "category": CAT_SUNSCREEN,
        "description": "Ultra-light watery sunscreen with micro defense. No white cast, perfect under makeup.",
        "original_price": 14.49,
        "discount_percent": 30,
        "concerns": [CONCERN_SUN, CONCERN_OILY, CONCERN_ALL],
        "buy_url": "https://www.amazon.com/dp/B0BKRPSCHY",
    },
    {
        "name": "Unseen Sunscreen SPF 40",
        "brand": "Supergoop!",
        "category": CAT_SUNSCREEN,
        "description": "Weightless, invisible, scentless SPF 40 that doubles as a makeup-gripping primer.",
        "original_price": 38.00,
        "discount_percent": 15,
        "concerns": [CONCERN_SUN, CONCERN_OILY, CONCERN_PORES, CONCERN_ALL],
        "buy_url": "https://www.amazon.com/dp/B09XN2L47T",
    },

    # ── Serums ──
    {
        "name": "Niacinamide 10% + Zinc 1%",
        "brand": "The Ordinary",
        "category": CAT_SERUM,
        "description": "High-strength vitamin and mineral blemish formula to reduce pores and balance oil.",
        "original_price": 6.50,
        "discount_percent": 30,
        "concerns": [CONCERN_ACNE, CONCERN_PORES, CONCERN_OILY],
        "buy_url": "https://www.amazon.com/dp/B06VRM5DQQ",
    },
    {
        "name": "Hyaluronic Acid 2% + B5",
        "brand": "The Ordinary",
        "category": CAT_SERUM,
        "description": "Multi-weight hyaluronic acid complex for deep hydration and plumper skin.",
        "original_price": 8.90,
        "discount_percent": 25,
        "concerns": [CONCERN_DRY, CONCERN_AGING, CONCERN_DULL, CONCERN_ALL],
        "buy_url": "https://www.amazon.com/dp/B01MYRGEWS",
    },
    {
        "name": "Vitamin C Serum CE Ferulic",
        "brand": "SkinCeuticals",
        "category": CAT_SERUM,
        "description": "Gold-standard 15% vitamin C with vitamin E and ferulic acid for brightening and anti-aging.",
        "original_price": 182.00,
        "discount_percent": 10,
        "concerns": [CONCERN_HYPERPIGMENTATION, CONCERN_AGING, CONCERN_DULL],
        "buy_url": "https://www.amazon.com/dp/B003IRL32A",
    },
    {
        "name": "Snail Mucin 96% Power Repairing Essence",
        "brand": "COSRX",
        "category": CAT_SERUM,
        "description": "Lightweight snail secretion filtrate essence for deep repair, hydration, and glow.",
        "original_price": 25.00,
        "discount_percent": 35,
        "concerns": [CONCERN_DRY, CONCERN_AGING, CONCERN_DULL, CONCERN_SENSITIVITY],
        "buy_url": "https://www.amazon.com/dp/B00PBX3L7K",
    },
    {
        "name": "Retinol 0.5% in Squalane",
        "brand": "The Ordinary",
        "category": CAT_SERUM,
        "description": "Stable retinol in squalane for fine lines, wrinkles, and skin texture improvement.",
        "original_price": 7.50,
        "discount_percent": 20,
        "concerns": [CONCERN_AGING, CONCERN_PORES, CONCERN_DULL],
        "buy_url": "https://www.amazon.com/dp/B01GWO2E3E",
    },
    {
        "name": "Alpha Arbutin 2% + HA",
        "brand": "The Ordinary",
        "category": CAT_SERUM,
        "description": "Concentrated alpha arbutin to visibly reduce dark spots and uneven skin tone.",
        "original_price": 9.60,
        "discount_percent": 25,
        "concerns": [CONCERN_HYPERPIGMENTATION, CONCERN_DULL],
        "buy_url": "https://www.amazon.com/dp/B071917RMY",
    },

    # ── Exfoliants ──
    {
        "name": "Skin Perfecting 2% BHA Liquid Exfoliant",
        "brand": "Paula's Choice",
        "category": CAT_EXFOLIANT,
        "description": "Legendary salicylic acid exfoliant that unclogs pores, smooths wrinkles, and brightens.",
        "original_price": 35.00,
        "discount_percent": 20,
        "concerns": [CONCERN_ACNE, CONCERN_PORES, CONCERN_OILY, CONCERN_DULL],
        "buy_url": "https://www.amazon.com/dp/B00949CTQQ",
    },
    {
        "name": "AHA 30% + BHA 2% Peeling Solution",
        "brand": "The Ordinary",
        "category": CAT_EXFOLIANT,
        "description": "10-minute exfoliating facial for brighter skin. Use max 2x per week.",
        "original_price": 8.50,
        "discount_percent": 15,
        "concerns": [CONCERN_DULL, CONCERN_HYPERPIGMENTATION, CONCERN_ACNE],
        "buy_url": "https://www.amazon.com/dp/B071D4D5DT",
    },

    # ── Toners ──
    {
        "name": "Facial Treatment Essence",
        "brand": "SK-II",
        "category": CAT_TONER,
        "description": "Iconic Japanese pitera essence for crystal-clear, radiant skin.",
        "original_price": 99.00,
        "discount_percent": 15,
        "concerns": [CONCERN_DULL, CONCERN_AGING, CONCERN_ALL],
        "buy_url": "https://www.amazon.com/dp/B00B12I8CW",
    },
    {
        "name": "AHA/BHA Clarifying Treatment Toner",
        "brand": "COSRX",
        "category": CAT_TONER,
        "description": "Gentle daily toner with natural BHA from white willow bark to minimize pores.",
        "original_price": 15.00,
        "discount_percent": 25,
        "concerns": [CONCERN_ACNE, CONCERN_PORES, CONCERN_OILY],
        "buy_url": "https://www.amazon.com/dp/B00OZ9WOD8",
    },

    # ── Spot Treatments ──
    {
        "name": "Acne Pimple Master Patch",
        "brand": "COSRX",
        "category": CAT_SPOT,
        "description": "Hydrocolloid patches that absorb pus and protect blemishes overnight.",
        "original_price": 7.99,
        "discount_percent": 30,
        "concerns": [CONCERN_ACNE],
        "buy_url": "https://www.amazon.com/dp/B014SAB948",
    },

    # ── Eye Creams ──
    {
        "name": "Retinol Eye Cream",
        "brand": "RoC",
        "category": CAT_EYE,
        "description": "Clinically proven retinol eye cream that reduces wrinkles and dark circles.",
        "original_price": 27.49,
        "discount_percent": 25,
        "concerns": [CONCERN_AGING],
        "buy_url": "https://www.amazon.com/dp/B00KHFNPGM",
    },
]


def get_products_for_concerns(
    concerns: list[str],
    limit: int = 3,
) -> list[dict]:
    """Return products matching the given skin concerns, sorted by relevance.

    Args:
        concerns: List of skin concern tags (e.g., ["acne", "oily"]).
        limit: Maximum number of products to return.

    Returns:
        List of matching products sorted by number of matching concerns (descending).
    """
    if not concerns:
        # Default to universal products
        concerns = [CONCERN_ALL]

    # Normalize concerns
    concerns_lower = [c.lower().strip() for c in concerns]

    scored = []
    for product in PRODUCT_CATALOG:
        product_concerns = [c.lower() for c in product["concerns"]]
        # Count how many user concerns this product addresses
        match_count = sum(1 for c in concerns_lower if c in product_concerns)
        # Also boost products tagged "all"
        if CONCERN_ALL in product_concerns:
            match_count += 0.5

        if match_count > 0:
            scored.append((match_count, product))

    # Sort by match count descending, then by discount descending
    scored.sort(key=lambda x: (x[0], x[1]["discount_percent"]), reverse=True)

    return [p for _, p in scored[:limit]]


def format_product_for_notification(product: dict) -> dict:
    """Format a product for push notification payload.

    Returns:
        dict with title, body, and data suitable for FCM notification.
    """
    discounted = product["original_price"] * (1 - product["discount_percent"] / 100)

    return {
        "title": f"🛍️ {product['discount_percent']}% OFF — {product['brand']} {product['name']}",
        "body": product["description"],
        "data": {
            "type": "product_discount",
            "product_name": product["name"],
            "brand": product["brand"],
            "category": product["category"],
            "original_price": f"${product['original_price']:.2f}",
            "discount_percent": str(product["discount_percent"]),
            "discounted_price": f"${discounted:.2f}",
            "buy_url": product["buy_url"],
        },
    }
