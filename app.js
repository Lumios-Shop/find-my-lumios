/**
 * ==========================================================================
 * LUMIOS INTERACTIVE MAP APPLICATION
 * Core Client-Side Logic
 * ==========================================================================
 */

document.addEventListener("DOMContentLoaded", () => {
    // Application State
    let map = null;
    let markerClusterGroup = null;
    let allStores = [];
    let filteredStores = [];
    let activeMarker = null;
    let activeStoreId = null;
    let userCoords = null;
    let userLocationMarker = null;
    const markerMap = new Map(); // Store ID -> Marker reference

    // Colors matching the Lumios ball game
    const LUMIOS_COLORS = ["blue", "green", "red", "orange", "pink"];

    // DOM Elements References
    const searchInput = document.getElementById("search-input");
    const clearSearchBtn = document.getElementById("clear-search-btn");
    const geolocationBtn = document.getElementById("geolocation-btn");
    const sidebarToggleBtn = document.getElementById("sidebar-toggle-btn");
    const sidebar = document.getElementById("sidebar");
    const storesList = document.getElementById("stores-list");
    const counterValue = document.getElementById("counter-value");
    const geoStatusIndicator = document.getElementById("geo-status-indicator");
    
    // Detail Card Elements
    const detailCard = document.getElementById("detail-card");
    const cardName = document.getElementById("card-name");
    const cardAddress = document.getElementById("card-address");
    const cardDistanceBadge = document.getElementById("card-distance-badge");
    const cardDistance = document.getElementById("card-distance");
    const cardDirectionsBtn = document.getElementById("card-directions-btn");
    const closeCardBtn = document.getElementById("close-card-btn");

    /**
     * Helper: Assigns a consistent brand color based on the store's name.
     */
    function getStoreColor(storeName) {
        let hash = 0;
        for (let i = 0; i < storeName.length; i++) {
            hash = storeName.charCodeAt(i) + ((hash << 5) - hash);
        }
        const index = Math.abs(hash) % LUMIOS_COLORS.length;
        return LUMIOS_COLORS[index];
    }

    /**
     * Helper: Haversine distance formula between two GPS coordinates in kilometers.
     */
    function getDistance(lat1, lon1, lat2, lon2) {
        const R = 6371; // Earth's radius in km
        const dLat = ((lat2 - lat1) * Math.PI) / 180;
        const dLon = ((lon2 - lon1) * Math.PI) / 180;
        const a =
            Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos((lat1 * Math.PI) / 180) *
                Math.cos((lat2 * Math.PI) / 180) *
                Math.sin(dLon / 2) *
                Math.sin(dLon / 2);
        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return R * c;
    }

    /**
     * 1. INITIALIZE LEAFLET MAP
     */
    function initMap() {
        // Center of France (approximate coordinates)
        const defaultCenter = [46.45, 2.2];
        const defaultZoom = 6;

        map = L.map("map", {
            zoomControl: true,
            minZoom: 5,
            maxZoom: 18,
            attributionControl: true
        }).setView(defaultCenter, defaultZoom);

        // CartoDB Dark Matter tile layer for an elegant night celestial feel
        L.tileLayer("https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png", {
            attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>',
            subdomains: "abcd",
            maxZoom: 20
        }).addTo(map);

        // Initialize Marker Cluster Group with custom styling
        markerClusterGroup = L.markerClusterGroup({
            showCoverageOnHover: false,
            zoomToBoundsOnClick: true,
            maxClusterRadius: 45,
            iconCreateFunction: function (cluster) {
                const count = cluster.getChildCount();
                let clusterSizeClass = "cluster-small";
                
                if (count >= 100) {
                    clusterSizeClass = "cluster-large";
                } else if (count >= 30) {
                    clusterSizeClass = "cluster-medium";
                }

                return L.divIcon({
                    html: `<div><span>${count}</span></div>`,
                    className: `custom-cluster ${clusterSizeClass}`,
                    iconSize: L.point(40, 40)
                });
            }
        });

        map.addLayer(markerClusterGroup);

        // Close details card on clicking anywhere on the map background
        map.on("click", (e) => {
            if (e.originalEvent.target.id === "map") {
                deselectActiveMarker();
                hideDetailCard();
            }
        });

        // Close mobile drawer when dragging the map
        map.on("dragstart", () => {
            if (window.innerWidth <= 960) {
                toggleSidebar(false);
            }
        });
    }

    /**
     * 2. LOAD STORE DATA FROM JSON
     */
    async function loadStoresData() {
        try {
            const response = await fetch("boutiques_geocoded.json");
            if (!response.ok) {
                throw new Error("Erreur de chargement du fichier JSON.");
            }
            const data = await response.json();
            
            // Filter out stores that were not successfully geocoded
            allStores = data.filter(store => store.lat !== null && store.lon !== null);
            filteredStores = [...allStores];
            
            counterValue.textContent = filteredStores.length;
            
            // Build Map Markers & List
            renderStoreMarkers();
            renderStoresList();
        } catch (error) {
            console.error("Failed to load stores:", error);
            storesList.innerHTML = `
                <div class="empty-placeholder">
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                    </svg>
                    <h3>Erreur</h3>
                    <p>Impossible de charger la liste des boutiques. Veuillez rafraîchir la page.</p>
                </div>
            `;
        }
    }

    /**
     * 3. RENDER MARKERS ON MAP
     */
    function renderStoreMarkers() {
        // Clear previous markers
        markerClusterGroup.clearLayers();
        markerMap.clear();

        filteredStores.forEach((store) => {
            const color = getStoreColor(store.nom);
            
            // Custom CSS marker icon representing glowing spheres
            const customIcon = L.divIcon({
                className: `custom-glow-marker marker-${color}`,
                html: '<div class="marker-pin"></div>',
                iconSize: [24, 24],
                iconAnchor: [12, 12]
            });

            // Create Marker
            const marker = L.marker([store.lat, store.lon], { icon: customIcon });
            
            // Store reference in properties
            marker.storeId = store.id;

            // Handle marker click events
            marker.on("click", (e) => {
                L.DomEvent.stopPropagation(e);
                selectStore(store, marker, true);
            });

            markerClusterGroup.addLayer(marker);
            markerMap.set(store.id, marker);
        });
    }

    /**
     * 4. RENDER LIST OF STORES IN SIDEBAR
     */
    function renderStoresList() {
        storesList.innerHTML = "";

        if (filteredStores.length === 0) {
            storesList.innerHTML = `
                <div class="empty-placeholder">
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                    </svg>
                    <h3>Aucun résultat</h3>
                    <p>Nous n'avons trouvé aucune boutique correspondant à votre recherche.</p>
                    <div class="online-shop-offer">
                        <p class="offer-title">Lumios est disponible en ligne !</p>
                        <p class="offer-desc">Commandez-le sur notre boutique officielle (livraison rapide) :</p>
                        <a href="https://www.lumios-le-jeu.fr" target="_blank" class="online-shop-btn">
                            Commander sur lumios-le-jeu.fr
                            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" class="btn-arrow-icon" style="width: 14px; height: 14px; display: inline; margin-left: 4px; vertical-align: middle;">
                                <path stroke-linecap="round" stroke-linejoin="round" d="M13.5 6H5.25A2.25 2.25 0 003 8.25v10.5A2.25 2.25 0 005.25 21h10.5A2.25 2.25 0 0018 18.75V10.5m-10.5 6L21 3m0 0h-5.25M21 3v5.25" />
                            </svg>
                        </a>
                    </div>
                </div>
            `;
            return;
        }

        filteredStores.forEach((store) => {
            const color = getStoreColor(store.nom);
            const item = document.createElement("div");
            item.className = `store-item ${store.id === activeStoreId ? 'active' : ''}`;
            item.dataset.id = store.id;

            // Distance markup if geolocation is active
            let distanceHtml = "";
            if (store.distance !== undefined) {
                distanceHtml = `
                    <div class="store-distance">
                        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor">
                            <path fill-rule="evenodd" d="M9.69 18.933l.003.001C9.89 19.02 10 19 10 19s.11.02.308-.066l.002-.001.006-.003.018-.008a5.741 5.741 0 00.281-.14c.186-.096.446-.24.757-.433.62-.384 1.445-.966 2.274-1.765C15.302 14.988 17 12.493 17 9.5a7 7 0 10-14 0c0 2.993 1.698 5.488 3.659 7.287.83.799 1.655 1.381 2.274 1.765.31.193.57.337.757.433.102.053.197.094.254.122a.502.502 0 00.027.012l.006.002zm3.81-11.933a3.5 3.5 0 11-7 0 3.5 3.5 0 017 0z" clip-rule="evenodd" />
                        </svg>
                        <span>${store.distance.toFixed(1)} km</span>
                    </div>
                `;
            }

            item.innerHTML = `
                <div class="store-name">${store.nom}</div>
                <div class="store-address">${store.adresse}</div>
                <div class="store-meta">
                    <div class="store-city">${store.city} (${store.postcode})</div>
                    ${distanceHtml}
                </div>
            `;

            // Click item handler
            item.addEventListener("click", () => {
                const marker = markerMap.get(store.id);
                selectStore(store, marker, false); // Do not center instantly, zoom in smoothly
                
                // On mobile, close the list drawer to show the map when selecting a store
                if (window.innerWidth <= 960) {
                    toggleSidebar(false);
                }
            });

            storesList.appendChild(item);
        });
    }

    /**
     * 5. SELECT A STORE & SHOW DETAILS
     */
    function selectStore(store, marker, wasMarkerClick = false) {
        deselectActiveMarker();
        activeStoreId = store.id;

        // Highlight list item in sidebar
        const listItems = storesList.querySelectorAll(".store-item");
        listItems.forEach((item) => {
            if (item.dataset.id === store.id) {
                item.classList.add("active");
                item.scrollIntoView({ behavior: "smooth", block: "nearest" });
            } else {
                item.classList.remove("active");
            }
        });

        // Set Marker Active (expansion & pulsating neon)
        if (marker) {
            activeMarker = marker;
            
            // Check if marker is in a cluster
            const parentCluster = markerClusterGroup.getVisibleParent(marker);
            
            // If the marker is inside a cluster currently, zoom to it first
            if (parentCluster && typeof parentCluster.getChildCount === 'function') {
                markerClusterGroup.zoomToShowLayer(marker, () => {
                    highlightMarkerEl(marker);
                });
            } else {
                highlightMarkerEl(marker);
                map.setView(marker.getLatLng(), 15, { animate: true, duration: 1.0 });
            }
        }

        // Show details in floating card
        showDetailCard(store);
    }

    /**
     * Adds the glowing CSS class directly to the Leaflet marker element.
     */
    function highlightMarkerEl(marker) {
        const el = marker.getElement();
        if (el) {
            el.classList.add("active-marker");
        }
    }

    /**
     * Remove the active glow state from the current marker.
     */
    function deselectActiveMarker() {
        if (activeMarker) {
            const el = activeMarker.getElement();
            if (el) {
                el.classList.remove("active-marker");
            }
            activeMarker = null;
        }
        activeStoreId = null;
        const listItems = storesList.querySelectorAll(".store-item");
        listItems.forEach(item => item.classList.remove("active"));
    }

    /**
     * 6. FLOATING BOTTOM SHEET / DETAIL CARD CONTROLS
     */
    function showDetailCard(store) {
        cardName.textContent = store.nom;
        cardAddress.textContent = `${store.adresse}, ${store.postcode} ${store.city}`;

        // Direction Routing Link
        cardDirectionsBtn.href = `https://www.google.com/maps/dir/?api=1&destination=${store.lat},${store.lon}`;

        if (store.distance !== undefined) {
            cardDistance.textContent = `À ${store.distance.toFixed(1)} km de vous`;
            cardDistanceBadge.style.display = "inline-flex";
        } else {
            cardDistanceBadge.style.display = "none";
        }

        detailCard.style.display = "block";
    }

    function hideDetailCard() {
        detailCard.style.display = "none";
    }

    closeCardBtn.addEventListener("click", () => {
        deselectActiveMarker();
        hideDetailCard();
    });

    /**
     * 7. SEARCH & FILTER LOGIC
     */
    function handleSearch() {
        const term = searchInput.value.toLowerCase().trim();

        if (term === "") {
            clearSearchBtn.style.display = "none";
            filteredStores = [...allStores];
        } else {
            clearSearchBtn.style.display = "flex";
            
            // Search criteria: Name, City, Postcode, Address
            filteredStores = allStores.filter((store) => {
                return (
                    store.nom.toLowerCase().includes(term) ||
                    store.city.toLowerCase().includes(term) ||
                    store.postcode.toLowerCase().includes(term) ||
                    store.adresse.toLowerCase().includes(term)
                );
            });
        }

        // Deselect active store if it has been filtered out
        if (activeStoreId && !filteredStores.some(s => s.id === activeStoreId)) {
            deselectActiveMarker();
            hideDetailCard();
        }

        // Re-sort by proximity if geolocation is active
        if (userCoords) {
            sortStoresByProximity();
        }

        // Update view
        counterValue.textContent = filteredStores.length;
        renderStoreMarkers();
        renderStoresList();

        // Adjust map view bounds to match search results
        adjustMapViewToFilteredStores();
    }

    /**
     * Helper to adjust map bounds/center based on currently filtered stores.
     */
    function adjustMapViewToFilteredStores() {
        if (filteredStores.length === 0) {
            return;
        }

        // If a store is currently active, we keep focusing on it
        if (activeStoreId && filteredStores.some(s => s.id === activeStoreId)) {
            return;
        }

        if (filteredStores.length === 1) {
            map.setView([filteredStores[0].lat, filteredStores[0].lon], 13);
        } else if (filteredStores.length < allStores.length) {
            // Fit bounds of filtered stores
            const bounds = L.latLngBounds(filteredStores.map(s => [s.lat, s.lon]));
            map.fitBounds(bounds, { padding: [50, 50], maxZoom: 15 });
        } else {
            // Reset to default center of France (search cleared)
            map.setView([46.45, 2.2], 6);
        }
    }

    searchInput.addEventListener("input", handleSearch);
    
    clearSearchBtn.addEventListener("click", () => {
        searchInput.value = "";
        deselectActiveMarker();
        hideDetailCard();
        handleSearch();
        searchInput.focus();
    });

    /**
     * 8. GEOLOCATION & PROXIMITY SORTING
     */
    function sortStoresByProximity() {
        filteredStores.forEach((store) => {
            store.distance = getDistance(
                userCoords.lat,
                userCoords.lon,
                store.lat,
                store.lon
            );
        });

        // Sort ascending
        filteredStores.sort((a, b) => a.distance - b.distance);
    }

    async function handleGeolocation() {
        if (!navigator.geolocation) {
            alert("La géolocalisation n'est pas supportée par votre navigateur.");
            return;
        }

        // Add loading state visual to button
        geolocationBtn.disabled = true;
        const initialText = geolocationBtn.innerHTML;
        geolocationBtn.innerHTML = `
            <div class="spinner" style="width:16px; height:16px; border-width:2px; margin-right:8px;"></div>
            <span>Recherche...</span>
        `;

        navigator.geolocation.getCurrentPosition(
            (position) => {
                userCoords = {
                    lat: position.coords.latitude,
                    lon: position.coords.longitude
                };

                // Place User pulse marker on map
                if (userLocationMarker) {
                    map.removeLayer(userLocationMarker);
                }

                const userIcon = L.divIcon({
                    className: "user-location-marker",
                    html: '<div class="user-pulse-core"></div><div class="user-pulse-ring"></div>',
                    iconSize: [32, 32],
                    iconAnchor: [16, 16]
                });

                userLocationMarker = L.marker([userCoords.lat, userCoords.lon], { icon: userIcon }).addTo(map);

                // Compute distances and sort
                allStores.forEach((store) => {
                    store.distance = getDistance(
                        userCoords.lat,
                        userCoords.lon,
                        store.lat,
                        store.lon
                    );
                });

                sortStoresByProximity();

                // Show Trié par proximité indicator
                geoStatusIndicator.style.display = "flex";

                // Re-render UI
                renderStoreMarkers();
                renderStoresList();

                // Zoom & center map on user coordinates
                map.setView([userCoords.lat, userCoords.lon], 11, { animate: true });

                // Reset Button
                geolocationBtn.disabled = false;
                geolocationBtn.innerHTML = initialText;
            },
            (error) => {
                console.error("Geolocation failed:", error);
                alert("Impossible de récupérer votre position géographique. Assurez-vous d'avoir autorisé l'accès.");
                geolocationBtn.disabled = false;
                geolocationBtn.innerHTML = initialText;
            },
            {
                enableHighAccuracy: true,
                timeout: 8000,
                maximumAge: 0
            }
        );
    }

    geolocationBtn.addEventListener("click", handleGeolocation);

    /**
     * 9. RESPONSIVE SIDEBAR MOBILE DRAWER CONTROLLER
     */
    function toggleSidebar(forceOpen = null) {
        const isOpen = forceOpen !== null ? forceOpen : !sidebar.classList.contains("open");
        const burgerIcon = sidebarToggleBtn.querySelector(".burger-icon");
        const closeIcon = sidebarToggleBtn.querySelector(".close-icon");

        if (isOpen) {
            sidebar.classList.add("open");
            burgerIcon.style.display = "none";
            closeIcon.style.display = "block";
        } else {
            sidebar.classList.remove("open");
            burgerIcon.style.display = "block";
            closeIcon.style.display = "none";
        }
    }

    sidebarToggleBtn.addEventListener("click", () => toggleSidebar());

    // Mobile layout adjustment: Inject search bar into mobile sidebar drawer
    function adjustSearchForMobile() {
        const searchSection = document.querySelector(".search-section");
        const header = document.querySelector(".app-header");
        
        if (window.innerWidth <= 960) {
            // If search is not already in sidebar, inject it
            if (!sidebar.querySelector(".sidebar-search-mobile")) {
                const searchMobileDiv = document.createElement("div");
                searchMobileDiv.className = "sidebar-search-mobile";
                
                // Move elements from header search section
                const wrapper = document.querySelector(".search-bar-wrapper");
                const geoBtn = document.getElementById("geolocation-btn");
                
                if (wrapper && geoBtn) {
                    searchMobileDiv.appendChild(wrapper);
                    searchMobileDiv.appendChild(geoBtn);
                    sidebar.insertBefore(searchMobileDiv, sidebar.firstChild);
                }
            }
        } else {
            // Desktop: restore search section in header
            const searchMobileDiv = sidebar.querySelector(".sidebar-search-mobile");
            if (searchMobileDiv) {
                const wrapper = searchMobileDiv.querySelector(".search-bar-wrapper");
                const geoBtn = searchMobileDiv.querySelector("#geolocation-btn");
                
                if (wrapper && geoBtn) {
                    searchSection.appendChild(wrapper);
                    searchSection.appendChild(geoBtn);
                }
                searchMobileDiv.remove();
            }
            toggleSidebar(false);
        }
    }

    window.addEventListener("resize", adjustSearchForMobile);

    // Initial Execution
    initMap();
    loadStoresData();
    adjustSearchForMobile(); // Run once at start
});
